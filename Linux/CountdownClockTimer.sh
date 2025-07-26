#!/bin/bash

# Target time (YYYY-MM-DD HH:MM:SS)
TARGET_DATE="2027-11-01 00:00:00"

# Function to draw fancy frame
draw_frame() {
  local content=("$@")
  local max_len=0

  # Find the max length
  for line in "${content[@]}"; do
    (( ${#line} > max_len )) && max_len=${#line}
  done

  local border_top="╔$(printf '═%.0s' $(seq 1 $((max_len + 2))))╗"
  local border_bot="╚$(printf '═%.0s' $(seq 1 $((max_len + 2))))╝"

  echo "$border_top"
  for line in "${content[@]}"; do
    printf "║ %-*s ║\n" "$max_len" "$line"
  done
  echo "$border_bot"
}

# Function to calculate the time difference and prepare content
get_countdown_content() {
  local now=$(date +%s)
  local target=$(date -d "$TARGET_DATE" +%s)
  local diff=$(( target - now ))

  if [ "$diff" -le 0 ]; then
    draw_frame "🎉 It's November 2027! 🎉"
    exit 0
  fi

  local minutes=$(( diff / 60 % 60 ))
  local hours=$(( diff / 3600 % 24 ))
  local days=$(( diff / 86400 % 30 ))
  local months=$(( diff / 2592000 )) # Approx 30-day months

  local content=(
    "$(printf "%02d Months %02d Days" "$months" "$days")"
    "$(printf "%02d Hours  %02d Minutes" "$hours" "$minutes")"
  )

  draw_frame "${content[@]}"
}

# Loop with random sleep
while true; do
  clear
  get_countdown_content
  sleep_time=$(( RANDOM % 20 + 1 ))
  echo ""
  echo "⏳ Next update in $sleep_time seconds..."
  sleep "$sleep_time"
done
