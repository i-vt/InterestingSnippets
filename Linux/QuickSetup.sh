#!/usr/bin/env bash

sudo apt update
sudo apt upgrade

sudo apt install curl tree python3-pip plocate
sudo apt install python3-venv

echo "-------[current ip]-------"
echo ""
curl https://api.ipify.org/
echo ""
