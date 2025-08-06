
#!/bin/bash
set -e

# -----------------------------
# CONFIGURATION
# -----------------------------
MYSQL_SUPERUSER="superuser"
MYSQL_SUPERPASS="StrongPassword123!"
BIND_ADDRESS="0.0.0.0"
MYSQL_CONF_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"
MYSQL_APT_DEB="mysql-apt-config_0.8.29-1_all.deb"

# -----------------------------
# APACHE + PHP INSTALLATION
# -----------------------------
echo "🌐 Updating package list..."
sudo apt-get update

echo "📦 Installing Apache..."
sudo apt-get install -y apache2

echo "🔄 Enabling and starting Apache..."
sudo systemctl enable apache2
sudo systemctl start apache2

echo "🛠️ Installing PHP and common extensions..."
sudo apt-get install -y php libapache2-mod-php php-mysql php-cli php-curl php-mbstring php-xml php-zip php-gd php-soap

echo "🔄 Restarting Apache to load PHP module..."
sudo systemctl restart apache2

echo "🧪 Creating PHP info file to test setup..."
echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/info.php > /dev/null

echo "🛡️ Allowing HTTP (port 80) and HTTPS (port 443) through UFW (if active)..."
if sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
fi

echo "✅ Apache and PHP installation complete!"
echo "📁 You can test PHP at: http://<your-server-ip>/info.php"

# -----------------------------
# MYSQL INSTALLATION & CONFIG
# -----------------------------
echo "🧹 Completely removing existing MySQL installation..."
sudo systemctl stop mysql || true
sudo apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* || true
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "🗑️ Removing MySQL data and config directories..."
sudo rm -rf /var/lib/mysql /var/log/mysql /etc/mysql

echo "🔧 Installing MySQL APT Repository package..."
if [ ! -f "$MYSQL_APT_DEB" ]; then
    wget https://dev.mysql.com/get/$MYSQL_APT_DEB
fi
sudo DEBIAN_FRONTEND=noninteractive dpkg -i $MYSQL_APT_DEB

echo "📦 Installing MySQL Server..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

echo "🚀 Starting MySQL service..."
sudo systemctl start mysql
sudo systemctl enable mysql

echo "🔒 Securing MySQL root account..."
AUTH_METHOD=$(sudo mysql -e "SELECT plugin FROM mysql.user WHERE User='root' AND Host='localhost';" --skip-column-names 2>/dev/null || echo "unknown")

if [[ "$AUTH_METHOD" == "auth_socket" ]] || [[ "$AUTH_METHOD" == "" ]]; then
    echo "Root user uses auth_socket or no plugin; switching to mysql_native_password..."
    sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_SUPERPASS}';
EOF
fi

mysql -uroot -p${MYSQL_SUPERPASS} <<EOF
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "👤 Creating superuser '${MYSQL_SUPERUSER}'..."
mysql -uroot -p${MYSQL_SUPERPASS} <<EOF
CREATE USER IF NOT EXISTS '${MYSQL_SUPERUSER}'@'%' IDENTIFIED BY '${MYSQL_SUPERPASS}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_SUPERUSER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "🌐 Configuring MySQL to allow remote access..."
sudo mkdir -p "$(dirname "$MYSQL_CONF_FILE")"
if grep -q "^bind-address" "$MYSQL_CONF_FILE" 2>/dev/null; then
  sudo sed -i "s/^bind-address.*/bind-address = ${BIND_ADDRESS}/" "$MYSQL_CONF_FILE"
else
  echo "bind-address = ${BIND_ADDRESS}" | sudo tee -a "$MYSQL_CONF_FILE"
fi

echo "🔄 Restarting MySQL service to apply changes..."
sudo systemctl restart mysql

echo "🛡️ Allowing MySQL through UFW (if active)..."
if sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow 3306/tcp
fi

# -----------------------------
# FINAL OUTPUT
# -----------------------------
echo "✅ MySQL setup complete!"
echo ""
echo "🔑 Superuser credentials:"
echo "    Username: ${MYSQL_SUPERUSER}"
echo "    Password: ${MYSQL_SUPERPASS}"
echo "    Host:     % (any IP)"
echo ""
echo "🔑 Root credentials:"
echo "    Username: root"
echo "    Password: ${MYSQL_SUPERPASS}"
echo "    Host:     localhost"
echo ""
echo "🚀 Setup completed successfully!"
