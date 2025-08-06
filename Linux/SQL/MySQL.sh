#!/bin/bash
set -e

MYSQL_SUPERUSER="superuser"
MYSQL_SUPERPASS="StrongPassword123!"
BIND_ADDRESS="0.0.0.0"
MYSQL_CONF_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"

echo "🧹 Completely removing existing MySQL installation..."
sudo systemctl stop mysql || true
sudo apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* || true
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "🗑️ Removing MySQL data directories..."
sudo rm -rf /var/lib/mysql
sudo rm -rf /var/log/mysql
sudo rm -rf /etc/mysql

echo "📦 Installing MySQL with preset root password..."
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_SUPERPASS}"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_SUPERPASS}"

echo "🔧 Installing MySQL Server..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

echo "🚀 Starting MySQL service..."
sudo systemctl start mysql
sudo systemctl enable mysql

echo "🔒 Securing MySQL installation..."
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
sudo mkdir -p /etc/mysql/mysql.conf.d/
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

echo "✅ MySQL setup complete!"
echo "🔑 Superuser credentials:"
echo "    Username: ${MYSQL_SUPERUSER}"
echo "    Password: ${MYSQL_SUPERPASS}"
echo "    Host:     % (any IP)"
echo ""
echo "🔑 Root credentials:"
echo "    Username: root"
echo "    Password: ${MYSQL_SUPERPASS}"
echo "    Host:     localhost"
