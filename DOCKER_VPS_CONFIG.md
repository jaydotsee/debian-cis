# Sane Default Configuration for Docker VPS

This guide provides a practical security hardening configuration for a cloud VPS hosting multiple Docker Compose stacks.

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/ovh/debian-cis.git
cd debian-cis
sudo cp debian/default /etc/default/cis-hardening
sudo sed -i "s#CIS_LIB_DIR=.*#CIS_LIB_DIR='$(pwd)'/lib#" /etc/default/cis-hardening
sudo sed -i "s#CIS_CHECKS_DIR=.*#CIS_CHECKS_DIR='$(pwd)'/bin/hardening#" /etc/default/cis-hardening
sudo sed -i "s#CIS_CONF_DIR=.*#CIS_CONF_DIR='$(pwd)'/etc#" /etc/default/cis-hardening
sudo sed -i "s#CIS_TMP_DIR=.*#CIS_TMP_DIR='$(pwd)'/tmp#" /etc/default/cis-hardening
sudo sed -i "s#CIS_VERSIONS_DIR=.*#CIS_VERSIONS_DIR='$(pwd)'/versions#" /etc/default/cis-hardening

# 2. Create configuration files
sudo ./bin/hardening.sh --create-config-files-only

# 3. Apply recommended configuration for Docker VPS
sudo ./bin/hardening.sh --set-hardening-level 2

# 4. Disable checks incompatible with Docker (see below)
# Edit the configuration files manually or use the commands below

# 5. Run audit to see current state
sudo ./bin/hardening.sh --audit

# 6. After reviewing, apply hardening
sudo ./bin/hardening.sh --apply
```

## Recommended Configuration

### Hardening Level: 2 (Basic Policy)
Start with level 2, which provides good security practices without breaking most systems.

```bash
sudo ./bin/hardening.sh --set-hardening-level 2
```

### Checks to DISABLE for Docker VPS

These checks conflict with Docker operation or are impractical for a Docker host:

```bash
# IP forwarding is REQUIRED for Docker networking
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_ip_forwarding.cfg

# IPv6 - keep enabled if your containers/apps need it
# Only disable if you're certain you don't need IPv6
# sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_ipv6.cfg

# USB storage might be needed for backups or data transfer
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_usb_storage.cfg

# Automounting can be useful for external storage
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_automounting.cfg

# These filesystem checks are less critical for VPS (no physical media)
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nodev.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nosuid.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_noexec.cfg
```

### Checks to ENABLE for Docker VPS

These are critical for a Docker-hosting VPS:

```bash
# Enable firewall - CRITICAL for cloud VPS
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/enable_firewall.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/ufw_is_installed.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/ufw_is_enabled.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/ufw_default_deny.cfg

# SSH hardening - SKIP if you've already hardened SSH
# Uncomment these if you want CIS to manage SSH configuration:
# sudo sed -i 's/status=disabled/status=audit/' etc/conf.d/disable_sshd_permitemptypasswords.cfg
# sudo sed -i 's/status=disabled/status=audit/' etc/conf.d/sshd_ciphers.cfg
# sudo sed -i 's/status=disabled/status=audit/' etc/conf.d/sshd_loglevel.cfg
# sudo sed -i 's/status=disabled/status=audit/' etc/conf.d/sshd_maxauthtries.cfg
# sudo sed -i 's/status=disabled/status=audit/' etc/conf.d/disable_x11_forwarding.cfg

# Password policies - important for user accounts
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/password_min_length.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/password_complexity.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/enable_pwquality.cfg

# Disable unnecessary network protocols
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/disable_dccp.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/disable_sctp.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/disable_rds.cfg
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/disable_tipc.cfg
```

### Checks to Consider (Evaluate Based on Your Needs)

```bash
# Audit logging (level 4) - Very detailed, can consume disk space
# Only enable if you need comprehensive audit trails
# etc/conf.d/install_auditd.cfg
# etc/conf.d/enable_auditd.cfg
# etc/conf.d/record_*.cfg (various audit rules)

# Partition separation (level 3) - Difficult to change after initial setup
# If you can set up separate partitions during VPS provisioning, do it
# etc/conf.d/var_log_partition.cfg
# etc/conf.d/var_tmp_partition.cfg
# etc/conf.d/home_partition.cfg

# AppArmor (level 3) - Can interfere with Docker containers
# Test thoroughly if enabling
# etc/conf.d/install_apparmor.cfg
# etc/conf.d/enable_apparmor.cfg
# etc/conf.d/enforcing_apparmor.cfg

# Time sync - Important for logs and certificates
sudo sed -i 's/status=disabled/status=enabled/' etc/conf.d/use_time_sync.cfg
```

## Docker-Specific Firewall Configuration

After enabling UFW, you'll need to configure it for Docker:

### Method 1: UFW with Docker (Recommended)

```bash
# Install UFW
sudo apt-get install ufw

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (CRITICAL - do this before enabling!)
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS for web services
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Configure UFW to work with Docker
# Edit /etc/ufw/after.rules and add at the end:
sudo tee -a /etc/ufw/after.rules << 'EOF'

# Docker bridge network
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j DROP
COMMIT
EOF

# Enable UFW
sudo ufw enable
```

### Method 2: Docker with Host Network Mode

If you use Docker with host networking, ensure you explicitly allow the ports:

```bash
# Example for various services
sudo ufw allow 8080/tcp comment 'App 1'
sudo ufw allow 3000/tcp comment 'App 2'
sudo ufw allow 5432/tcp from 10.0.0.0/8 comment 'PostgreSQL from private network'
```

## Post-Hardening Verification

```bash
# 1. Run audit again
sudo ./bin/hardening.sh --audit

# 2. Check SSH still works (open a NEW terminal before closing current one!)
ssh user@your-vps-ip

# 3. Test Docker functionality
docker ps
docker-compose up -d

# 4. Check firewall rules
sudo ufw status verbose

# 5. Review logs for issues
sudo journalctl -xe
tail -f /var/log/syslog
```

## Common Issues and Solutions

### Issue: SSH Locked Out
**Prevention**: Always test SSH in a new session before closing your current one.
**Solution**: Use cloud provider's console/VNC to access the server and fix `/etc/ssh/sshd_config`

### Issue: Docker Containers Can't Access Internet
**Cause**: IP forwarding disabled or firewall blocking Docker traffic
**Solution**:
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Check Docker iptables rules
sudo iptables -L -n -v
```

### Issue: Can't Access Docker Container Ports
**Cause**: UFW blocking Docker published ports
**Solution**: Use the Docker-User chain configuration (Method 1 above) or explicitly allow ports

### Issue: High Audit Log Disk Usage
**Cause**: Comprehensive auditd logging enabled
**Solution**:
```bash
# Disable detailed auditing rules
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/record_*.cfg
# Or configure log rotation
sudo vi /etc/audit/auditd.conf  # Adjust max_log_file and num_logs
```

## Maintenance

```bash
# Regular security updates
sudo apt-get update && sudo apt-get upgrade -y

# Re-run audit monthly
sudo ./bin/hardening.sh --audit

# Check for new CIS checks
cd debian-cis && git pull
sudo ./bin/hardening.sh --audit-all
```

## Configuration Summary for Copy-Paste

Here's a complete configuration script you can save and run:

```bash
#!/bin/bash
set -e

# Navigate to debian-cis directory
cd /path/to/debian-cis

# Set hardening level 2
sudo ./bin/hardening.sh --set-hardening-level 2

# Disable Docker-incompatible checks
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_ip_forwarding.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_usb_storage.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_automounting.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nodev.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nosuid.cfg
sudo sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_noexec.cfg

# Enable critical security checks (SSH checks excluded - manage separately)
for check in enable_firewall ufw_is_installed ufw_is_enabled ufw_default_deny \
             password_min_length password_complexity enable_pwquality \
             disable_dccp disable_sctp disable_rds disable_tipc use_time_sync; do
  sudo sed -i 's/status=disabled/status=enabled/' "etc/conf.d/${check}.cfg" 2>/dev/null || true
done

# Optional: Set SSH checks to audit mode only (won't modify existing config)
# for check in disable_sshd_permitemptypasswords sshd_ciphers sshd_loglevel \
#              sshd_maxauthtries disable_x11_forwarding; do
#   sudo sed -i 's/status=disabled/status=audit/' "etc/conf.d/${check}.cfg" 2>/dev/null || true
# done

echo "Configuration complete! Review with: sudo ./bin/hardening.sh --audit"
```

## Risk Assessment

| Category | Level 2 Risk | Mitigation |
|----------|-------------|------------|
| SSH Lockout | Low-Medium | Test in new session, keep console access |
| Docker Network Break | Low | IP forwarding exception documented |
| Service Disruption | Low | Most checks are non-breaking |
| False Positives | Medium | Some checks may fail due to VPS environment |
| Audit Log Space | Low | Level 2 doesn't enable verbose auditing |

## Next Steps

1. Apply Level 2 configuration
2. Run audit and review failures
3. Gradually enable Level 3 checks after testing
4. Consider Level 4 (audit logging) only if required for compliance
5. Document any custom exceptions in `etc/conf.d/*.cfg` files
