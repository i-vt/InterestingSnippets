echo "CPU: $(nproc) cores | RAM: $(free -h | awk '/Mem:/ {print $2}') | Disk: $(df -h / | awk 'NR==2 {print $2}') | OS: $(. /etc/os-release && echo $PRETTY_NAME)"
