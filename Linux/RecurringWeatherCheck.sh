#!/bin/bash

while true; do
  clear
  echo "Weather in London (updated: $(date))"
  echo "-------------------------------------"
  curl -s https://wttr.in/London
  echo ""
  echo "Next update in 1 hour..."
  sleep 3600
done
