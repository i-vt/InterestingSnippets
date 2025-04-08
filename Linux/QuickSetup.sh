#!/usr/bin/env bash

sudo apt update
sudo apt upgrade

sudo apt install curl tree python3-pip plocate snapd
sudo apt install python3-venv

wget https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Linux/.vimrc --output-document=~/.vimrc


echo "-------[current ip]-------"
echo ""
curl https://api.ipify.org/
echo ""
