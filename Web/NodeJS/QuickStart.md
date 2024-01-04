# Quick Start with NodeJS (Ubuntu)

## Install NPM & NodeJS

### Using NodeSource
```
#Latest:
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
#LTS:
#curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Using APT only
```
sudo apt update
sudo apt install nodejs
sudo apt install npm
```

## Check version and update existing
```
node --version
npm --version
sudo npm install npm@latest -g
```
