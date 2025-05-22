root@srv718962:~# cat 1.sh 
#!/bin/bash

set -e

DOMAIN="advertisement-telemetry.com"
SSL_DIR="/root/ssl"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
WEB_ROOT="/var/www/$DOMAIN/html"
FULLCHAIN_PATH="/etc/ssl/certs/$DOMAIN.fullchain.crt"
KEY_PATH="/etc/ssl/private/$DOMAIN.key"

echo "🔧 Installing NGINX..."
apt update && apt install -y nginx

echo "🧹 Stopping Apache to free ports 80/443 if running..."
systemctl stop apache2 || true
systemctl disable apache2 || true
killall apache2 || true

echo "📁 Creating web root directory..."
mkdir -p "$WEB_ROOT"
chown -R www-data:www-data "$WEB_ROOT"

echo "🌐 Creating default index.html..."
echo "<h1>Welcome to $DOMAIN</h1>" > "$WEB_ROOT/index.html"
chown www-data:www-data "$WEB_ROOT/index.html"

echo "🔐 Extracting and preparing SSL certificates from .p7b..."
openssl pkcs7 -print_certs -in "$SSL_DIR/advertisement-telemetry_com.p7b" | \
awk '/BEGIN/{c++} { print > "/tmp/fullchain-cert-" c ".pem" }'

cat /tmp/fullchain-cert-*.pem > "$FULLCHAIN_PATH"
cp "$SSL_DIR/server.key" "$KEY_PATH"

chmod 644 "$FULLCHAIN_PATH"
chmod 600 "$KEY_PATH"

echo "📝 Creating NGINX config for $DOMAIN..."

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    root $WEB_ROOT;
    index index.html;

    ssl_certificate $FULLCHAIN_PATH;
    ssl_certificate_key $KEY_PATH;

    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_prefer_server_ciphers off;
    ssl_ecdh_curve X25519:secp384r1;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1h;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

echo "📡 Enabling site and restarting NGINX..."

rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

nginx -t
systemctl restart nginx

echo "✅ NGINX is installed and configured for $DOMAIN with TLS 1.3, X25519, and HTTP/2."
