#!/bin/bash
# CIS Hardening Configuration Script for Docker VPS
# This script configures debian-cis for a Docker-hosting VPS environment
#
# Usage: sudo ./configure-docker-vps.sh [OPTIONS]
#
# Options:
#   --ssh-port PORT        Custom SSH port (default: 49222)
#   --skip-firewall        Skip UFW firewall configuration
#   --audit-only           Set up for audit mode only (no apply)
#   --help                 Show this help message

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
SSH_PORT=49222
SKIP_FIREWALL=0
AUDIT_ONLY=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --skip-firewall)
            SKIP_FIREWALL=1
            shift
            ;;
        --audit-only)
            AUDIT_ONLY=1
            shift
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //'
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Get the actual user who ran sudo (if applicable)
REAL_USER=${SUDO_USER:-$USER}

# Check if we're in the debian-cis directory
if [[ ! -f "bin/hardening.sh" ]] || [[ ! -d "etc/conf.d" ]]; then
    error "This script must be run from the debian-cis repository root directory"
    exit 1
fi

CIS_DIR="$(pwd)"

info "Starting CIS Hardening configuration for Docker VPS"
info "SSH Port: $SSH_PORT"
info "CIS Directory: $CIS_DIR"
echo ""

# Step 1: Install /etc/default/cis-hardening
info "Step 1: Configuring /etc/default/cis-hardening"
if [[ -f /etc/default/cis-hardening ]]; then
    warn "/etc/default/cis-hardening already exists. Creating backup..."
    cp /etc/default/cis-hardening /etc/default/cis-hardening.backup.$(date +%Y%m%d-%H%M%S)
fi

cp debian/default /etc/default/cis-hardening
sed -i "s#CIS_LIB_DIR=.*#CIS_LIB_DIR='${CIS_DIR}'/lib#" /etc/default/cis-hardening
sed -i "s#CIS_CHECKS_DIR=.*#CIS_CHECKS_DIR='${CIS_DIR}'/bin/hardening#" /etc/default/cis-hardening
sed -i "s#CIS_CONF_DIR=.*#CIS_CONF_DIR='${CIS_DIR}'/etc#" /etc/default/cis-hardening
sed -i "s#CIS_TMP_DIR=.*#CIS_TMP_DIR='${CIS_DIR}'/tmp#" /etc/default/cis-hardening
sed -i "s#CIS_VERSIONS_DIR=.*#CIS_VERSIONS_DIR='${CIS_DIR}'/versions#" /etc/default/cis-hardening

success "Configured /etc/default/cis-hardening"

# Step 2: Create configuration files
info "Step 2: Creating configuration files"
./bin/hardening.sh --create-config-files-only
success "Configuration files created"

# Step 3: Set hardening level to 2
info "Step 3: Setting hardening level to 2 (Basic Policy)"
./bin/hardening.sh --set-hardening-level 2
success "Hardening level set to 2"

# Step 4: Disable checks incompatible with Docker
info "Step 4: Disabling Docker-incompatible checks"

# IP forwarding - REQUIRED for Docker
sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_ip_forwarding.cfg
success "  ✓ Disabled IP forwarding check (Docker needs this)"

# USB and removable media - less relevant for VPS
sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_usb_storage.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_automounting.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nodev.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_nosuid.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/removable_device_noexec.cfg 2>/dev/null || true
success "  ✓ Disabled USB/removable media checks (not relevant for VPS)"

# Disable wireless and Bluetooth checks (not applicable to VPS)
sed -i 's/status=enabled/status=disabled/' etc/conf.d/disable_wireless.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/wireless_interfaces_disabled.cfg 2>/dev/null || true
sed -i 's/status=enabled/status=disabled/' etc/conf.d/bluetooth_is_disabled.cfg 2>/dev/null || true
success "  ✓ Disabled wireless/bluetooth checks (not applicable to VPS)"

# Step 5: Enable critical security checks
info "Step 5: Enabling critical security checks"

# Firewall
for check in enable_firewall ufw_is_installed ufw_is_enabled ufw_default_deny; do
    if [[ -f "etc/conf.d/${check}.cfg" ]]; then
        sed -i 's/status=disabled/status=enabled/' "etc/conf.d/${check}.cfg"
    fi
done
success "  ✓ Enabled firewall checks"

# Password policies
for check in password_min_length password_complexity enable_pwquality install_libpam_pwquality; do
    if [[ -f "etc/conf.d/${check}.cfg" ]]; then
        sed -i 's/status=disabled/status=enabled/' "etc/conf.d/${check}.cfg"
    fi
done
success "  ✓ Enabled password policy checks"

# Disable unnecessary network protocols
for check in disable_dccp disable_sctp disable_rds disable_tipc; do
    if [[ -f "etc/conf.d/${check}.cfg" ]]; then
        sed -i 's/status=disabled/status=enabled/' "etc/conf.d/${check}.cfg"
    fi
done
success "  ✓ Enabled checks to disable unnecessary network protocols"

# Time synchronization
if [[ -f "etc/conf.d/use_time_sync.cfg" ]]; then
    sed -i 's/status=disabled/status=enabled/' "etc/conf.d/use_time_sync.cfg"
fi
success "  ✓ Enabled time synchronization check"

# Step 6: Set SSH checks to audit-only mode
info "Step 6: Setting SSH checks to audit-only mode"
for check in disable_sshd_permitemptypasswords sshd_ciphers sshd_loglevel \
             sshd_maxauthtries disable_x11_forwarding sshd_protocol \
             sshd_idle_timeout ssh_auth_pubk_only; do
    if [[ -f "etc/conf.d/${check}.cfg" ]]; then
        sed -i 's/status=enabled/status=audit/' "etc/conf.d/${check}.cfg"
        sed -i 's/status=disabled/status=audit/' "etc/conf.d/${check}.cfg"
    fi
done
success "  ✓ SSH checks set to audit mode (won't modify your existing SSH config)"

# Step 7: Create tmp directory if it doesn't exist
info "Step 7: Creating temporary directory for backups"
mkdir -p "${CIS_DIR}/tmp/backups"
chown -R "$REAL_USER:$REAL_USER" "${CIS_DIR}/tmp" 2>/dev/null || true
success "Created ${CIS_DIR}/tmp/backups"

echo ""
success "✅ Configuration complete!"
echo ""

# Step 8: Configure UFW if not skipped
if [[ $SKIP_FIREWALL -eq 0 ]]; then
    info "Step 8: Configuring UFW firewall"

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        warn "UFW not installed. Installing..."
        apt-get update -qq
        apt-get install -y ufw
    fi

    # Configure UFW
    info "Configuring UFW rules..."

    # Don't enable UFW yet - just configure it
    ufw --force default deny incoming
    ufw --force default allow outgoing

    # Allow SSH on custom port
    ufw allow ${SSH_PORT}/tcp comment 'SSH'
    success "  ✓ Allowed SSH on port ${SSH_PORT}"

    # Allow HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    success "  ✓ Allowed HTTP (80) and HTTPS (443)"

    # Configure Docker integration
    info "Configuring UFW for Docker compatibility..."

    # Backup existing after.rules if it exists
    if [[ -f /etc/ufw/after.rules ]]; then
        cp /etc/ufw/after.rules /etc/ufw/after.rules.backup.$(date +%Y%m%d-%H%M%S)
    fi

    # Check if Docker rules already exist
    if ! grep -q "DOCKER-USER" /etc/ufw/after.rules 2>/dev/null; then
        cat >> /etc/ufw/after.rules << 'EOF'

# BEGIN DOCKER INTEGRATION
# Allow Docker containers to communicate
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j DROP
COMMIT
# END DOCKER INTEGRATION
EOF
        success "  ✓ Added Docker integration rules to UFW"
    else
        info "  Docker rules already exist in UFW configuration"
    fi

    warn ""
    warn "⚠️  UFW has been configured but NOT enabled yet!"
    warn "⚠️  To enable UFW, run: sudo ufw enable"
    warn "⚠️  Make sure you can access SSH on port ${SSH_PORT} before enabling!"
    warn ""
else
    info "Step 8: Skipping UFW configuration (--skip-firewall specified)"
fi

# Step 9: Run initial audit
info "Step 9: Running initial audit to check current compliance"
echo ""
info "This may take a minute..."
echo ""

./bin/hardening.sh --audit 2>&1 | tee "${CIS_DIR}/tmp/initial-audit.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "🎉 CIS Hardening configuration completed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "Audit results saved to: ${CIS_DIR}/tmp/initial-audit.log"
echo ""
info "Next steps:"
echo "  1. Review the audit results above"
echo "  2. If you skipped UFW setup, configure your firewall manually"
if [[ $SKIP_FIREWALL -eq 0 ]]; then
    echo "  3. Enable UFW: sudo ufw enable"
    echo "  4. Verify SSH access on port ${SSH_PORT} works!"
fi
if [[ $AUDIT_ONLY -eq 0 ]]; then
    echo "  5. Apply hardening: sudo ./bin/hardening.sh --apply"
    echo "  6. Run final audit: sudo ./bin/hardening.sh --audit"
else
    info "Audit-only mode: No apply needed"
fi
echo ""
warn "⚠️  IMPORTANT: Test SSH access in a NEW terminal before closing this one!"
echo ""
