sudo apt-get update && sudo apt-get install -y gnupg curl wget
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall
bashsudo msfdb init    # first-time setup
sudo msfdb start   # if already initialized
msfconsole

# Verify: msf> db_status
