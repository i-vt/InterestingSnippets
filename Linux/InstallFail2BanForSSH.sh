#!/bin/bash

# Fail2ban SSH Installation Script for Debian
# This script installs and configures fail2ban to protect SSH

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

print_status "Starting fail2ban installation and configuration..."

# Update package list
print_status "Updating package list..."
apt update

# Install fail2ban
print_status "Installing fail2ban..."
apt install -y fail2ban

# Create jail.local configuration file
print_status "Creating fail2ban configuration..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban time in seconds (10 minutes)
bantime = 600

# Find time window in seconds (10 minutes)
findtime = 600

# Maximum number of failures before ban
maxretry = 5

# Destination email for notifications (optional)
# destemail = admin@yourdomain.com

# Sender email (optional)
# sender = fail2ban@yourdomain.com

# Email actions (optional - requires mail setup)
# action = %(action_mw)s

# Default action (just ban, no email)
action = %(action_)s

[sshd]
# Enable SSH protection
enabled = true

# Port to monitor (change if SSH runs on different port)
port = ssh

# Filter to use
filter = sshd

# Log file to monitor
logpath = /var/log/auth.log

# Maximum retry attempts
maxretry = 3

# Ban time for SSH (30 minutes)
bantime = 1800

# Find time window (10 minutes)
findtime = 600
EOF

# Create a custom filter for additional SSH protection (optional)
print_status "Creating additional SSH filter..."
cat > /etc/fail2ban/filter.d/sshd-aggressive.conf << 'EOF'
# Additional aggressive SSH filter
[Definition]
failregex = ^%(__prefix_line)s(?:error: PAM: )?[aA]uthentication (?:failure|error) for .* from <HOST>( via \S+)?\s*$
            ^%(__prefix_line)s(?:error: )?Received disconnect from <HOST>: 3: .*: Auth fail \[preauth\]\s*$
            ^%(__prefix_line)sFailed (?:password|publickey) for .* from <HOST>(?: port \d*)?(?: ssh\d*)?\s*$
            ^%(__prefix_line)sROOT LOGIN REFUSED.* FROM <HOST>\s*$
            ^%(__prefix_line)s[iI](?:llegal|nvalid) user .* from <HOST>\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because not listed in AllowUsers\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because listed in DenyUsers\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because not in any group\s*$
            ^%(__prefix_line)srefused connect from \S+ \(<HOST>\)\s*$
            ^%(__prefix_line)sReceived disconnect from <HOST>: 11: Bye Bye \[preauth\]\s*$
            ^%(__prefix_line)sConnection closed by <HOST> \[preauth\]\s*$
            ^%(__prefix_line)sConnection closed by <HOST> port \d+ \[preauth\]\s*$

ignoreregex = 
EOF

# Enable and start fail2ban service
print_status "Enabling and starting fail2ban service..."
systemctl enable fail2ban
systemctl start fail2ban

# Wait a moment for service to fully start
sleep 2

# Check service status
if systemctl is-active --quiet fail2ban; then
    print_success "Fail2ban service is running"
else
    print_error "Fail2ban service failed to start"
    exit 1
fi

# Display current status
print_status "Current fail2ban status:"
fail2ban-client status

# Display SSH jail status
print_status "SSH jail status:"
fail2ban-client status sshd

# Create a simple management script
print_status "Creating management script..."
cat > /usr/local/bin/f2b-manage << 'EOF'
#!/bin/bash
# Simple fail2ban management script

case "$1" in
    status)
        echo "=== Fail2ban Status ==="
        fail2ban-client status
        echo ""
        echo "=== SSH Jail Status ==="
        fail2ban-client status sshd
        ;;
    unban)
        if [ -z "$2" ]; then
            echo "Usage: $0 unban <IP_ADDRESS>"
            exit 1
        fi
        echo "Unbanning IP: $2"
        fail2ban-client set sshd unbanip "$2"
        ;;
    banned)
        echo "=== Currently Banned IPs ==="
        fail2ban-client get sshd banip
        ;;
    restart)
        echo "Restarting fail2ban..."
        systemctl restart fail2ban
        echo "Done."
        ;;
    logs)
        echo "=== Recent fail2ban logs ==="
        tail -n 20 /var/log/fail2ban.log
        ;;
    *)
        echo "Usage: $0 {status|unban <ip>|banned|restart|logs}"
        echo ""
        echo "Commands:"
        echo "  status  - Show fail2ban and SSH jail status"
        echo "  unban   - Unban a specific IP address"
        echo "  banned  - Show currently banned IPs"
        echo "  restart - Restart fail2ban service"
        echo "  logs    - Show recent fail2ban log entries"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/f2b-manage

# Display configuration summary
print_success "Fail2ban installation and configuration completed!"
echo ""
print_status "Configuration Summary:"
echo "  • SSH protection: ENABLED"
echo "  • Max retries: 3 attempts"
echo "  • Ban time: 30 minutes"
echo "  • Find time: 10 minutes"
echo "  • Monitored log: /var/log/auth.log"
echo ""
print_status "Management:"
echo "  • Check status: f2b-manage status"
echo "  • View logs: f2b-manage logs"
echo "  • Unban IP: f2b-manage unban <IP>"
echo "  • View banned IPs: f2b-manage banned"
echo ""
print_status "Configuration files:"
echo "  • Main config: /etc/fail2ban/jail.local"
echo "  • Service status: systemctl status fail2ban"
echo ""
print_warning "Important Notes:"
echo "  • Make sure you have alternative access (console/KVM) in case you get locked out"
echo "  • Consider adding your trusted IP to ignoreip in /etc/fail2ban/jail.local"
echo "  • Monitor /var/log/fail2ban.log for activity"
echo ""
print_success "Your server is now protected against SSH brute force attacks!"
