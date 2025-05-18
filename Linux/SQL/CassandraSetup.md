# Installer Script

```
#!/bin/bash

set -e

echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y gnupg curl openjdk-11-jdk

echo "Adding Apache Cassandra GPG key..."
curl https://downloads.apache.org/cassandra/KEYS | sudo gpg --dearmor -o /usr/share/keyrings/cassandra-archive-keyring.gpg

echo "Adding Apache Cassandra APT repository..."
echo "deb [signed-by=/usr/share/keyrings/cassandra-archive-keyring.gpg] https://downloads.apache.org/cassandra/debian 311x main" | sudo tee /etc/apt/sources.list.d/cassandra.list

echo "Updating package index..."
sudo apt-get update

echo "Installing Cassandra..."
sudo apt-get install -y cassandra

echo "Starting Cassandra service..."
sudo systemctl enable cassandra
sudo systemctl start cassandra

```
