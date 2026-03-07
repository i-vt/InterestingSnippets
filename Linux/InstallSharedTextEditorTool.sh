#!/usr/bin/env bash

set -e

APP_NAME="shared-text-editor"
APP_DIR="/opt/$APP_NAME"
SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
SCRIPT_URL="https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Web/NodeJS/SharedTextEditorAndFileshare.js"
SCRIPT_NAME="SharedTextEditorAndFileshare.js"
PORT=3000

echo "=============================="
echo "Installing dependencies"
echo "=============================="

sudo apt update

sudo apt install -y curl git

# Install NodeJS if not installed

if ! command -v node &> /dev/null
then
echo "Installing NodeJS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
fi

echo "Node version:"
node -v
echo "NPM version:"
npm -v

echo "=============================="
echo "Creating application directory"
echo "=============================="

sudo mkdir -p $APP_DIR
sudo chown $USER:$USER $APP_DIR

cd $APP_DIR

echo "=============================="
echo "Downloading application"
echo "=============================="

curl -L $SCRIPT_URL -o $SCRIPT_NAME

echo "=============================="
echo "Initializing npm project"
echo "=============================="

npm init -y

echo "=============================="
echo "Installing dependencies"
echo "=============================="

npm install express socket.io multer

echo "=============================="
echo "Creating systemd service"
echo "=============================="

sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Shared Text Editor and File Share
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/$SCRIPT_NAME
Restart=always
RestartSec=5
Environment=PORT=$PORT

[Install]
WantedBy=multi-user.target
EOF

echo "=============================="
echo "Reloading systemd"
echo "=============================="

sudo systemctl daemon-reload

echo "=============================="
echo "Starting service"
echo "=============================="

sudo systemctl enable $APP_NAME
sudo systemctl restart $APP_NAME

sleep 3

echo "=============================="
echo "Service status"
echo "=============================="

sudo systemctl status $APP_NAME --no-pager

echo "=============================="
echo "Testing HTTP endpoint"
echo "=============================="

if curl -s [http://localhost:$PORT](http://localhost:$PORT) > /dev/null
then
echo "SUCCESS: Server responding at [http://localhost:$PORT](http://localhost:$PORT)"
else
echo "WARNING: Server not responding yet"
fi

echo "=============================="
echo "Installation complete"
echo "=============================="

echo "Open in browser:"
echo "[http://localhost:$PORT](http://localhost:$PORT)"
