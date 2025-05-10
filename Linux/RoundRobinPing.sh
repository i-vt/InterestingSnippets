#!/bin/bash
# Works great to keep the connection alive & prevents WiFi idle/session timeout in corporate envs. 
domains=(
  google.com bing.com yahoo.com msn.com
  microsoft.com apple.com amazon.com linkedin.com
  ibm.com oracle.com salesforce.com adobe.com
  intel.com nvidia.com dell.com hp.com
  lenovo.com cisco.com sap.com zoom.us
  cloudflare.com slack.com dropbox.com box.com
  atlassian.com github.com stackoverflow.com trello.com
  airbnb.com uber.com paypal.com stripe.com
  walmart.com target.com costco.com fedex.com
  dhl.com ups.com bbc.com nytimes.com
  theguardian.com cnn.com bloomberg.com forbes.com
  reuters.com
)

while true; do
  for domain in "${domains[@]}"; do
    result=$(ping -c 1 -W 1 "$domain" | grep "bytes from" || echo "No response")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $domain - $result"
  done
  sleep 1
done
