#!/bin/bash

set -e

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install Java (Cassandra requires Java 8 or 11)
echo "Installing OpenJDK 11..."
sudo apt-get install -y openjdk-11-jdk

# Add the Apache Cassandra repository
echo "Adding Apache Cassandra repository..."
echo "deb https://downloads.apache.org/cassandra/debian 40x main" | sudo tee /etc/apt/sources.list.d/cassandra.list

# Import the repository's GPG key
curl https://downloads.apache.org/cassandra/KEYS | sudo apt-key add -

# Update package index with Cassandra repo
echo "Updating package index with Cassandra repo..."
sudo apt-get update

# Install Cassandra
echo "Installing Apache Cassandra..."
sudo apt-get install -y cassandra

# Enable and start the Cassandra service
echo "Enabling and starting Cassandra service..."
sudo systemctl enable cassandra
sudo systemctl start cassandra

# Check service status
echo "Cassandra installation complete. Checking service status..."
sudo systemctl status cassandra
