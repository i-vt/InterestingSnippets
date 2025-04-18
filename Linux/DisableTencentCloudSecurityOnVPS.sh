# https://www.trendmicro.com/en_us/research/24/h/cve-2023-22527-cryptomining.html
# Check if any process related to "YunJing" is running (case-insensitive)
if ps aux | grep -i '[y]unjing'; then
  # Define a list of process names to look for
  process=(sap100 secu-tcs-agent sgagent64 barad_agent agent agentPlugInD pvdriver )

  # Loop through each process name
  for i in ${process[@]}
  do
    # Find process IDs (PIDs) for the current process name, excluding the grep process itself
    for A in $(ps aux | grep $i | grep -v grep | awk '{print $2}')
    do
      # Forcefully kill the process with the found PID
      kill -9 $A
    done
  done

  # Disable postfix service at runlevel 3 and 5
  chkconfig --level 35 postfix off

  # Stop the postfix service
  service postfix stop

  # Run uninstall and stop scripts for various qcloud components
  /usr/local/qcloud/stargate/admin/stop.sh
  /usr/local/qcloud/stargate/admin/uninstall.sh
  /usr/local/qcloud/YunJing/uninst.sh
  /usr/local/qcloud/monitor/barad/admin/stop.sh
  /usr/local/qcloud/monitor/barad/admin/uninstall.sh

  # Remove various qcloud and security agent directories
  rm -rf /usr/local/sa
  rm -rf /usr/local/agenttools
  rm -rf /usr/local/qcloud

  # Remove a specific cron task related to sgagent
  rm -f /etc/cron.d/sgagenttask
fi

# Wait for 1 second
sleep 1

# Print confirmation message
echo "DER Uninstalled"
