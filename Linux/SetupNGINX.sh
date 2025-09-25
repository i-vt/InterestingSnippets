#!/bin/bash
# Enhanced Nginx setup script with SSL for static sites
# Usage: sudo ./setup_nginx.sh example.com [email@domain.com]
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Parse arguments
if [ -z "$1" ]; then
    error "Usage: $0 <domain> [email]"
    error "Example: $0 example.com admin@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=${2:-""}
WEBROOT="/var/www/$DOMAIN/html"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
BACKUP_DIR="/tmp/nginx-backup-$(date +%s)"

# Validate domain format
validate_domain() {
    if [[ ! $DOMAIN =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        error "Invalid domain format: $DOMAIN"
        exit 1
    fi
}

# Check DNS resolution
check_dns() {
    log "Checking DNS resolution for $DOMAIN..."
    
    # Get server's public IP
    SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "unknown")
    
    if [ "$SERVER_IP" = "unknown" ]; then
        warn "Could not determine server's public IP"
        warn "Please ensure $DOMAIN resolves to this server's IP"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return
    fi
    
    # Check if domain resolves to server IP
    DOMAIN_IP=$(dig +short $DOMAIN | tail -n1 2>/dev/null || echo "")
    
    if [ -z "$DOMAIN_IP" ]; then
        error "Domain $DOMAIN does not resolve to any IP"
        error "Please configure DNS to point $DOMAIN to $SERVER_IP"
        exit 1
    fi
    
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        warn "Domain $DOMAIN resolves to $DOMAIN_IP but server IP is $SERVER_IP"
        warn "SSL certificate generation may fail"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log "DNS resolution confirmed: $DOMAIN -> $SERVER_IP"
    fi
}

# Validate or prompt for email
get_email() {
    if [ -z "$EMAIL" ]; then
        read -p "Enter email for Let's Encrypt notifications: " EMAIL
    fi
    
    # Basic email validation
    if [[ ! $EMAIL =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $EMAIL"
        exit 1
    fi
    
    log "Using email: $EMAIL"
}

# Create backup directory
create_backup() {
    mkdir -p "$BACKUP_DIR"
    log "Created backup directory: $BACKUP_DIR"
    
    # Backup existing nginx config if it exists
    if [ -f "$NGINX_CONF" ]; then
        cp "$NGINX_CONF" "$BACKUP_DIR/"
        log "Backed up existing nginx config"
    fi
}

# Rollback function
rollback() {
    error "Installation failed. Rolling back changes..."
    
    # Remove nginx config
    [ -f "$NGINX_CONF" ] && rm -f "$NGINX_CONF"
    [ -L "$NGINX_ENABLED" ] && rm -f "$NGINX_ENABLED"
    
    # Restore backup if it exists
    if [ -f "$BACKUP_DIR/$DOMAIN" ]; then
        cp "$BACKUP_DIR/$DOMAIN" "$NGINX_CONF"
        ln -sf "$NGINX_CONF" "$NGINX_ENABLED"
        log "Restored previous nginx config"
    fi
    
    # Reload nginx
    systemctl reload nginx 2>/dev/null || true
    
    error "Rollback completed. Check logs above for the cause of failure."
    exit 1
}

# Set trap for cleanup
trap rollback ERR

# Check if site already exists
check_existing() {
    if [ -f "$NGINX_CONF" ]; then
        warn "Configuration for $DOMAIN already exists"
        read -p "Overwrite existing configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Keeping existing configuration"
            exit 0
        fi
    fi
}

# Install packages
install_packages() {
    log "Updating package lists..."
    apt update -y
    
    log "Installing required packages..."
    # Fixed: dig -> dnsutils
    apt install -y nginx certbot python3-certbot-nginx ufw curl dnsutils
    
    # Verify installations - added curl and dig
    for cmd in nginx certbot ufw curl dig; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd installation failed"
            exit 1
        fi
    done
    
    log "All packages installed successfully"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Enable UFW if not already enabled - improved check
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        warn "UFW firewall is not active"
        read -p "Enable UFW firewall? (recommended) (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ufw --force enable
        fi
    fi
    
    # Add firewall rules
    ufw allow 'Nginx Full' 2>/dev/null || {
        ufw allow 80/tcp
        ufw allow 443/tcp
    }
    
    log "Firewall configured for HTTP/HTTPS"
}

# Start and enable nginx
setup_nginx() {
    log "Starting and enabling Nginx..."
    systemctl enable nginx
    systemctl start nginx
    
    if ! systemctl is-active --quiet nginx; then
        error "Failed to start Nginx"
        exit 1
    fi
    
    log "Nginx is running"
}

# Create web directory and files
setup_webroot() {
    log "Setting up web directory..."
    
    # Create directory structure
    mkdir -p "$WEBROOT/images"
    mkdir -p "/var/www/$DOMAIN/logs"
    
    # Set proper ownership and permissions
    chown -R www-data:www-data "/var/www/$DOMAIN"
    chmod -R 755 "/var/www/$DOMAIN"
    
    # Create sample index.html if it doesn't exist
    if [ ! -f "$WEBROOT/index.html" ]; then
        cat > "$WEBROOT/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .status { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to $DOMAIN!</h1>
        <p class="status">✅ Your static site is working perfectly.</p>
        <p>This is a sample page. Replace this file at <code>$WEBROOT/index.html</code> with your own content.</p>
        <hr>
        <small>Generated by nginx-setup script on $(date)</small>
    </div>
</body>
</html>
EOF
        chown www-data:www-data "$WEBROOT/index.html"
    fi
    
    log "Web directory created at $WEBROOT"
}

# Create initial nginx configuration (HTTP only)
create_initial_config() {
    log "Creating initial Nginx configuration..."
    
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root $WEBROOT;
    index index.html index.htm;
    
    # Logging
    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log;
    
    # Security headers (basic)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /images/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
    
    # Security: deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
    
    # Enable the site
    ln -sf "$NGINX_CONF" "$NGINX_ENABLED"
    
    # Test configuration
    if ! nginx -t; then
        error "Nginx configuration test failed"
        exit 1
    fi
    
    systemctl reload nginx
    log "Initial configuration created and activated"
}

# Test HTTP access
test_http() {
    log "Testing HTTP access..."
    sleep 2
    
    if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN/" | grep -q "200"; then
        log "HTTP test successful"
    else
        warn "HTTP test failed - continuing anyway"
    fi
}

# Obtain SSL certificate
obtain_ssl() {
    log "Obtaining SSL certificate from Let's Encrypt..."
    
    # Check rate limits (basic check)
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        warn "SSL certificate already exists for $DOMAIN"
        read -p "Renew certificate? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Keeping existing certificate"
            return
        fi
    fi
    
    # Attempt to get certificate
    if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect; then
        log "SSL certificate obtained successfully"
    else
        error "Failed to obtain SSL certificate"
        warn "Site is still accessible via HTTP at http://$DOMAIN"
        exit 1
    fi
}

# Update configuration with enhanced security
enhance_security() {
    log "Enhancing security configuration..."
    
    # Create enhanced HTTPS configuration
    cat > "$NGINX_CONF" <<EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    root $WEBROOT;
    index index.html index.htm;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!SRP:!CAMELLIA;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # HSTS (optional, uncomment to enable)
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; media-src 'self'; object-src 'none'; child-src 'self'; frame-ancestors 'self'; form-action 'self'; base-uri 'self';" always;
    
    # Logging
    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log;
    
    # Main location block
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Images with directory listing
    location /images/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
    
    # Security: deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Optional: deny access to backup files
    location ~ ~$ {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
    
    # Test and reload
    if nginx -t; then
        systemctl reload nginx
        log "Security enhancements applied"
    else
        error "Security configuration failed"
        exit 1
    fi
}

# Test HTTPS access
test_https() {
    log "Testing HTTPS access..."
    sleep 3
    
    if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/" | grep -q "200"; then
        log "HTTPS test successful"
    else
        warn "HTTPS test failed"
    fi
}

# Setup log rotation
setup_logrotation() {
    log "Setting up log rotation..."
    
    cat > "/etc/logrotate.d/$DOMAIN" <<EOF
/var/www/$DOMAIN/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log "Log rotation configured"
}

# Setup auto-renewal
setup_autorenewal() {
    log "Setting up SSL auto-renewal..."
    
    # Try to enable certbot timer, but don't fail if it doesn't exist
    if systemctl list-unit-files | grep -q "certbot.timer"; then
        if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
            log "SSL auto-renewal is already configured"
        else
            systemctl enable certbot.timer
            systemctl start certbot.timer
            log "SSL auto-renewal timer enabled"
        fi
    else
        # Alternative: check if certbot is in crontab
        if crontab -l 2>/dev/null | grep -q certbot; then
            log "SSL auto-renewal is configured via cron"
        else
            warn "Could not find certbot timer or cron job"
            warn "You may need to set up SSL renewal manually"
        fi
    fi
    
    # Test renewal (dry run)
    if certbot renew --dry-run >/dev/null 2>&1; then
        log "SSL renewal test passed"
    else
        warn "SSL renewal test failed - manual intervention may be required"
    fi
}

# Final summary
show_summary() {
    echo
    log "🎉 Setup completed successfully!"
    echo
    echo "📋 Summary:"
    echo "  • Domain: $DOMAIN"
    echo "  • Document root: $WEBROOT"
    echo "  • Nginx config: $NGINX_CONF"
    echo "  • SSL certificate: /etc/letsencrypt/live/$DOMAIN/"
    echo "  • Log files: /var/www/$DOMAIN/logs/"
    echo
    echo "🌐 Your site is now accessible at:"
    echo "  • https://$DOMAIN"
    echo "  • https://www.$DOMAIN"
    echo
    echo "📝 Next steps:"
    echo "  • Replace $WEBROOT/index.html with your content"
    echo "  • Upload images to $WEBROOT/images/ for directory listing"
    echo "  • Monitor logs in /var/www/$DOMAIN/logs/"
    echo
    echo "🔧 Useful commands:"
    echo "  • Test nginx config: nginx -t"
    echo "  • Reload nginx: systemctl reload nginx"
    echo "  • Check SSL: certbot certificates"
    echo "  • Renew SSL: certbot renew"
    echo
}

# Main execution
main() {
    log "Starting Nginx setup for $DOMAIN"
    
    validate_domain
    check_dns
    get_email
    create_backup
    check_existing
    install_packages
    configure_firewall
    setup_nginx
    setup_webroot
    create_initial_config
    test_http
    obtain_ssl
    enhance_security
    test_https
    setup_logrotation
    setup_autorenewal
    
    # Cleanup
    rm -rf "$BACKUP_DIR"
    
    show_summary
}

# Run main function
main "$@"
