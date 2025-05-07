#!/bin/bash

LOCATION="$1"

if [ -z "$LOCATION" ]; then
  echo "Usage: $0 <location>"
  exit 1
fi

INTERVAL=3600  # 1 hour in seconds

while true; do
  clear
  CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
  NEXT_UPDATE_TIME=$(date -d "+$INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
  
  echo "Weather in $LOCATION (updated: $CURRENT_TIME)"
  echo "----------------------------------------------"
  curl -s "https://wttr.in/${LOCATION}" | grep -vE '^(Follow|Location|Weather report)'
  echo ""
  echo "Next update at $NEXT_UPDATE_TIME (in 1 hour)..."
  sleep $INTERVAL
done
