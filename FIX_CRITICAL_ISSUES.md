# Fix Critical Issues Before Apply

This guide addresses the critical security issues found in the audit, with proper handling of the passwordless sudo configuration.

## 1. Revert Sudoers Change (If You Need NOPASSWD)

If you changed `/etc/sudoers.d/90-cloud-init-users` and want to keep passwordless sudo:

```bash
# Revert to original
echo "skdm ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-cloud-init-users
sudo chmod 440 /etc/sudoers.d/90-cloud-init-users
```

## 2. Add User to CIS Hardening Exceptions

Instead of removing NOPASSWD, add your user to the exceptions list:

```bash
# Edit the check configuration
sudo vi ~/debian-cis/etc/conf.d/99.1.3_acc_sudoers_no_all.cfg
```

Add your username to the EXCEPTIONS line:

```bash
# Configuration for script of same name
status=enabled
# Put here sudo entities (users, groups...) that are exceptions.
# If a user or group should be able to execute any command on any host, add it here.
EXCEPTIONS="root %sudo skdm"
```

This tells the CIS hardening script that `skdm` with full sudo rights is intentional and approved.

## 3. Enable Sudo Logging

Add logging to track sudo usage:

```bash
# Create sudo logging configuration
echo 'Defaults logfile="/var/log/sudo.log"' | sudo tee /etc/sudoers.d/00-sudo-logging
sudo chmod 440 /etc/sudoers.d/00-sudo-logging

# Create the log file with correct permissions
sudo touch /var/log/sudo.log
sudo chmod 600 /var/log/sudo.log
```

Verify it works:
```bash
sudo ls
sudo cat /var/log/sudo.log
```

## 4. Restrict Core Dumps

Prevent core dumps from leaking sensitive information:

```bash
# Add to limits.conf
echo "* hard core 0" | sudo tee -a /etc/security/limits.conf

# Verify sysctl setting (should already be correct)
sudo sysctl fs.suid_dumpable
# Should output: fs.suid_dumpable = 0
```

## 5. Fix Home Directory Permissions

Your home directory allows "other" users to read/execute:

```bash
# Remove read/execute for others
chmod 750 /home/skdm

# Verify
ls -ld /home/skdm
# Should show: drwxr-x--- (750)
```

## 6. Fix SSH Config Permissions

```bash
sudo chmod 600 /etc/ssh/sshd_config

# Verify
ls -l /etc/ssh/sshd_config
# Should show: -rw------- (600)
```

## 7. Install Password Quality Library

This will be installed when you run apply, but you can do it now:

```bash
sudo apt update
sudo apt install -y libpam-pwquality
```

## 8. Add Timeout for Shell Sessions (Optional but Recommended)

Auto-logout inactive sessions after 10 minutes:

```bash
# Create timeout configuration
sudo tee /etc/profile.d/timeout.sh << 'EOF'
# Auto-logout after 10 minutes of inactivity
TMOUT=600
readonly TMOUT
export TMOUT
EOF

sudo chmod 644 /etc/profile.d/timeout.sh
```

**Note**: This will auto-logout your shell after 10 minutes of inactivity. Adjust `TMOUT` value as needed (in seconds).

## 9. Create Cron Access Control Files

Restrict who can use cron/at:

```bash
# Remove deny files
sudo rm -f /etc/at.deny /etc/cron.deny

# Create allow files (only listed users can use cron/at)
echo "root" | sudo tee /etc/cron.allow
echo "skdm" | sudo tee -a /etc/cron.allow  # Add your user
echo "root" | sudo tee /etc/at.allow
echo "skdm" | sudo tee -a /etc/at.allow   # Add your user

# Set correct permissions
sudo chmod 600 /etc/cron.allow /etc/at.allow
sudo chown root:root /etc/cron.allow /etc/at.allow
```

## 10. Handle IPv6 Decision

You need to decide whether to keep or disable IPv6:

### Option A: Disable IPv6 Completely (Recommended if not needed)

```bash
# Add to sysctl
sudo tee -a /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

# Apply immediately
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

# Verify
ip a | grep inet6
# Should show nothing except ::1/128 on lo
```

### Option B: Keep IPv6 Enabled and Secure It

If you need IPv6, the hardening script will secure it when you run `--apply`. No action needed now.

## 11. Add Exception for Docker Socket

The ungrouped file warning for docker socket is normal:

```bash
# Edit the check configuration
sudo vi ~/debian-cis/etc/conf.d/6.1.12_find_ungrouped_files.cfg
```

Add the docker socket path to exceptions:

```bash
# Configuration for script of same name
status=enabled
# Put here your exceptions concerning ungrouped files, space separated
EXCEPTIONS="/run/user/1000/docker.sock"
```

## Verification Checklist

After making these changes, verify:

```bash
# 1. Sudo logging works
sudo ls
sudo cat /var/log/sudo.log  # Should show the previous command

# 2. Core dumps restricted
ulimit -c  # Should output: 0

# 3. Home directory permissions
ls -ld /home/skdm  # Should be drwxr-x---

# 4. SSH config permissions
ls -l /etc/ssh/sshd_config  # Should be -rw-------

# 5. Cron access files exist
ls -l /etc/cron.allow /etc/at.allow  # Should both exist with 600 perms

# 6. Password quality installed
dpkg -l | grep libpam-pwquality  # Should show installed
```

## Summary of Changes Made

| Issue | Fix | Security Impact |
|-------|-----|-----------------|
| NOPASSWD sudo | Added to exceptions | ✅ Tracked, approved exception |
| No sudo logging | Enabled logging | ✅ All sudo commands tracked |
| Core dumps enabled | Disabled | ✅ Prevents data leaks |
| Home dir readable | Fixed permissions | ✅ Prevents info disclosure |
| SSH config readable | Fixed permissions | ✅ Protects SSH config |
| No cron restrictions | Added allow files | ✅ Limits cron access |
| No password policy | Installed pwquality | ✅ Enforces strong passwords |
| No session timeout | Added TMOUT | ✅ Auto-logout inactive sessions |

## Next Steps

After completing these fixes:

1. **Update the exception in CIS config** (most important!)
2. **Run audit again** to verify fixes:
   ```bash
   cd ~/debian-cis
   sudo ./bin/hardening.sh --audit
   ```

3. **Review the new results** - should see:
   - `99.1.3_acc_sudoers_no_all`: Now PASSES (exception added)
   - `1.3.3_logfile_sudo`: Now PASSES (logging enabled)
   - `1.6.4_restrict_core_dumps`: Now PASSES (core dumps disabled)
   - Improved permission checks

4. **Proceed with apply**:
   ```bash
   sudo ./bin/hardening.sh --apply
   ```

5. **Enable UFW**:
   ```bash
   sudo ufw enable
   ```

6. **Final verification**:
   ```bash
   sudo ./bin/hardening.sh --audit
   docker ps  # Verify Docker still works
   ```
