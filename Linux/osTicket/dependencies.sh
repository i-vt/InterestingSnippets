#!/bin/bash

# Update and upgrade the system
echo "Updating the system..."
sudo apt update && sudo apt upgrade -y

# Install Apache Web Server
echo "Installing Apache..."
sudo apt install apache2 -y
sudo systemctl start apache2
sudo systemctl enable apache2

# Install MySQL Server
echo "Installing MySQL..."
sudo apt install mysql-server -y
sudo systemctl start mysql
sudo systemctl enable mysql

# Secure MySQL Installation (you will be prompted to set up a MySQL root password)
echo "Securing MySQL..."
sudo mysql_secure_installation

# Install PHP and necessary extensions for osTicket
echo "Installing PHP and required extensions..."
sudo apt install php libapache2-mod-php php-cli php-mysql php-mbstring php-intl php-xml php-imap php-gd php-zip php-curl -y

# Enable necessary Apache modules
echo "Enabling Apache modules..."
sudo a2enmod rewrite
sudo phpenmod mbstring intl
sudo systemctl restart apache2

# Set up MySQL Database for osTicket
echo "Creating MySQL database for osTicket..."
mysql -u root -p -e "CREATE DATABASE osticket_db;"
mysql -u root -p -e "CREATE USER 'osticket_user'@'localhost' IDENTIFIED BY 'your_secure_password';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON osticket_db.* TO 'osticket_user'@'localhost';"
mysql -u root -p -e "FLUSH PRIVILEGES;"

# Download and install osTicket
echo "Downloading osTicket..."
cd /tmp
wget https://github.com/osTicket/osTicket/releases/download/v1.17.2/osTicket-v1.17.2.zip

echo "Unzipping osTicket..."
unzip osTicket-v1.17.2.zip -d /var/www/html/osticket

# Set correct permissions
echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/html/osticket
sudo chmod -R 755 /var/www/html/osticket

# Configure Apache Virtual Host for osTicket on localhost
echo "Configuring Apache virtual host for osTicket on localhost..."
cat <<EOT | sudo tee /etc/apache2/sites-available/osticket.conf
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/osticket/upload
    ServerName localhost
    <Directory /var/www/html/osticket/upload>
        AllowOverride All
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOT

# Enable the new site and disable the default site, then reload Apache
echo "Enabling osTicket site and disabling default site..."
sudo a2dissite 000-default.conf
sudo a2ensite osticket.conf
sudo systemctl reload apache2

# Final message
echo "Installation complete! You can now finish osTicket setup by visiting http://localhost in your browser."
