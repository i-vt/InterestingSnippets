#!/bin/bash

set -e

# -----------------------
# Configuration Variables
# -----------------------
MYSQL_SUPERUSER="superuser"
MYSQL_SUPERPASS="StrongPassword123!"
BIND_ADDRESS="0.0.0.0"
MYSQL_CONF_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"

echo "🔧 Installing MySQL Server..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

echo "🚀 Starting MySQL service..."
sudo systemctl start mysql

echo "🔒 Securing MySQL (non-interactive)..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_SUPERPASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "👤 Creating superuser '${MYSQL_SUPERUSER}'..."
sudo mysql -uroot -p${MYSQL_SUPERPASS} <<EOF
CREATE USER IF NOT EXISTS '${MYSQL_SUPERUSER}'@'%' IDENTIFIED BY '${MYSQL_SUPERPASS}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_SUPERUSER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "🌐 Configuring MySQL to allow remote access..."
if grep -q "^bind-address" "$MYSQL_CONF_FILE"; then
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
