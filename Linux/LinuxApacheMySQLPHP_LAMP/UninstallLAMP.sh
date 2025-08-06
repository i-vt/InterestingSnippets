#!/bin/bash

echo "Starting full LAMP stack uninstallation..."

# Stop services
echo "Stopping Apache and MySQL/MariaDB..."
sudo systemctl stop apache2 2>/dev/null
sudo systemctl stop mysql 2>/dev/null
sudo systemctl stop mariadb 2>/dev/null

# Uninstall Apache
echo "Removing Apache..."
sudo apt purge apache2 apache2-utils apache2-bin apache2.2-common -y
sudo rm -rf /etc/apache2

# Uninstall MySQL and MariaDB
echo "Removing MySQL/MariaDB..."
sudo apt purge mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* -y
sudo apt purge mariadb-server mariadb-client mariadb-common -y
sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
sudo deluser mysql 2>/dev/null
sudo delgroup mysql 2>/dev/null

# Uninstall PHP
echo "Removing PHP..."
sudo apt purge 'php*' -y
sudo rm -rf /etc/php

# Cleanup
echo "Performing autoremove and autoclean..."
sudo apt autoremove --purge -y
sudo apt autoclean

# Final check
echo "Checking for remaining LAMP packages..."
dpkg -l | grep -E 'apache|mysql|mariadb|php'

echo "LAMP stack uninstallation complete."
