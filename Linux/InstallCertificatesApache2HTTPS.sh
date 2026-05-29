#!/usr/bin/env bash
# =============================================================================
# setup_apache_https.sh
# Installs Apache2, obtains a Let's Encrypt TLS certificate via Certbot,
# and configures automatic HTTP → HTTPS redirection.
#
# Usage:
#   sudo bash setup_apache_https.sh -d example.com [-d www.example.com] -e admin@example.com
#
# Requirements:
#   - Ubuntu/Debian (or any distro with apt)
#   - Ports 80 and 443 open in your firewall
#   - DNS A/AAAA record for each domain pointing to this server
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run this script as root (sudo)."

# ── Argument parsing ──────────────────────────────────────────────────────────
DOMAINS=()
EMAIL=""

usage() {
  echo "Usage: $0 -d <domain> [-d <domain> ...] -e <email>"
  echo "  -d  Domain name (repeat for multiple, e.g. example.com www.example.com)"
  echo "  -e  Email for Let's Encrypt expiry notices"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain) DOMAINS+=("$2"); shift 2 ;;
    -e|--email)  EMAIL="$2";      shift 2 ;;
    -h|--help)   usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ ${#DOMAINS[@]} -gt 0 ]] || die "At least one domain is required (-d example.com)."
[[ -n "$EMAIL" ]]          || die "Email is required (-e admin@example.com)."

PRIMARY_DOMAIN="${DOMAINS[0]}"
WEBROOT="/var/www/${PRIMARY_DOMAIN}"
VHOST_CONF="/etc/apache2/sites-available/${PRIMARY_DOMAIN}.conf"
VHOST_SSL_CONF="/etc/apache2/sites-available/${PRIMARY_DOMAIN}-ssl.conf"

# ── Step 1 — System update & Apache install ───────────────────────────────────
info "Updating package lists…"
apt-get update -qq

info "Installing Apache2…"
apt-get install -y -qq apache2

# Enable required Apache modules
info "Enabling Apache modules (ssl, rewrite, headers)…"
a2enmod ssl rewrite headers
success "Apache modules enabled."

# ── Step 2 — Document root ────────────────────────────────────────────────────
info "Creating document root: ${WEBROOT}"
mkdir -p "${WEBROOT}"
chown -R www-data:www-data "${WEBROOT}"

# Default index page (only if one doesn't already exist)
if [[ ! -f "${WEBROOT}/index.html" ]]; then
  cat > "${WEBROOT}/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>${PRIMARY_DOMAIN}</title></head>
<body><h1>${PRIMARY_DOMAIN} is live!</h1><p>Secured with Let's Encrypt TLS.</p></body>
</html>
HTML
  success "Default index.html created."
fi

# ── Step 3 — HTTP VirtualHost (needed for ACME challenge) ────────────────────
info "Writing HTTP VirtualHost: ${VHOST_CONF}"
cat > "${VHOST_CONF}" <<APACHE
<VirtualHost *:80>
    ServerName ${PRIMARY_DOMAIN}
$(for d in "${DOMAINS[@]:1}"; do echo "    ServerAlias ${d}"; done)
    DocumentRoot ${WEBROOT}

    # Allow Let's Encrypt ACME challenges through before the HTTPS redirect
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]

    <Directory "${WEBROOT}">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/${PRIMARY_DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${PRIMARY_DOMAIN}-access.log combined
</VirtualHost>
APACHE

a2ensite "${PRIMARY_DOMAIN}.conf"
a2dissite 000-default.conf 2>/dev/null || true
systemctl reload apache2
success "HTTP VirtualHost enabled."

# ── Step 4 — Certbot install ─────────────────────────────────────────────────
if ! command -v certbot &>/dev/null; then
  info "Installing Certbot (snap)…"
  apt-get install -y -qq snapd
  snap install core          &>/dev/null || true
  snap refresh  core         &>/dev/null || true
  snap install --classic certbot &>/dev/null
  ln -sf /snap/bin/certbot /usr/bin/certbot
  success "Certbot installed via snap."
else
  success "Certbot already installed ($(certbot --version 2>&1))."
fi

# ── Step 5 — Obtain certificate ───────────────────────────────────────────────
info "Requesting Let's Encrypt certificate for: ${DOMAINS[*]}"

DOMAIN_ARGS=()
for d in "${DOMAINS[@]}"; do
  DOMAIN_ARGS+=("-d" "$d")
done

certbot certonly \
  --webroot \
  --webroot-path "${WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${EMAIL}" \
  --keep-until-expiring \
  "${DOMAIN_ARGS[@]}"

CERT_DIR="/etc/letsencrypt/live/${PRIMARY_DOMAIN}"
success "Certificate obtained: ${CERT_DIR}"

# ── Step 6 — HTTPS VirtualHost ───────────────────────────────────────────────
info "Writing HTTPS VirtualHost: ${VHOST_SSL_CONF}"
cat > "${VHOST_SSL_CONF}" <<APACHE
<VirtualHost *:443>
    ServerName ${PRIMARY_DOMAIN}
$(for d in "${DOMAINS[@]:1}"; do echo "    ServerAlias ${d}"; done)
    DocumentRoot ${WEBROOT}

    # ── TLS configuration ────────────────────────────────────────────────────
    SSLEngine on
    SSLCertificateFile      ${CERT_DIR}/fullchain.pem
    SSLCertificateKeyFile   ${CERT_DIR}/privkey.pem

    # Modern TLS settings (Mozilla Intermediate profile)
    SSLProtocol             all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:\
ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:\
ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:\
DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder     off
    SSLSessionTickets       off

    # ── Security headers ─────────────────────────────────────────────────────
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Content-Type-Options    "nosniff"
    Header always set X-Frame-Options           "SAMEORIGIN"
    Header always set Referrer-Policy           "strict-origin-when-cross-origin"
    Header always set Permissions-Policy        "geolocation=(), microphone=(), camera=()"

    <Directory "${WEBROOT}">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/${PRIMARY_DOMAIN}-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/${PRIMARY_DOMAIN}-ssl-access.log combined
</VirtualHost>
APACHE

a2ensite "${PRIMARY_DOMAIN}-ssl.conf"
systemctl reload apache2
success "HTTPS VirtualHost enabled."

# ── Step 7 — Auto-renewal verification ───────────────────────────────────────
info "Verifying Certbot auto-renewal timer…"
if systemctl list-timers --all | grep -q "certbot"; then
  success "Certbot systemd timer is active — certificates will renew automatically."
elif crontab -l 2>/dev/null | grep -q certbot; then
  success "Certbot cron job found — certificates will renew automatically."
else
  warn "No auto-renewal timer found. Adding a cron job as fallback…"
  CRON_LINE="0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload apache2'"
  (crontab -l 2>/dev/null; echo "${CRON_LINE}") | crontab -
  success "Cron job added: daily renewal check at 03:00."
fi

# Dry-run to confirm renewal works
info "Running certbot renew --dry-run to validate renewal pipeline…"
certbot renew --dry-run --quiet && success "Dry-run renewal succeeded." \
  || warn "Dry-run renewal failed — check certbot logs at /var/log/letsencrypt/."

# ── Step 8 — Final status ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "  Primary domain : https://${PRIMARY_DOMAIN}"
echo -e "  Certificate    : ${CERT_DIR}"
echo -e "  HTTP → HTTPS   : 301 redirect active"
echo -e "  Auto-renewal   : enabled (Certbot)"
echo -e "  HSTS           : max-age=63072000, includeSubDomains, preload"
echo ""
echo -e "  Test your SSL grade at: ${CYAN}https://www.ssllabs.com/ssltest/analyze.html?d=${PRIMARY_DOMAIN}${NC}"
echo ""
