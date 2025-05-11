# Postgres
## Basic setup

### Download
```
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql postgresql-client
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

### Minimal config
Start the PostgreSQL CLI
```
sudo -u postgres psql
```

Configure a basic user:
```
CREATE USER superuser WITH PASSWORD 'password';
ALTER USER superuser WITH SUPERUSER;
\q
```


### Enable remote access
Edit settings postgreesql.conf
```
sudo vi /etc/postgresql/<version>/main/postgresql.conf
```
Change line to uncommented and replace localhost with a star or something more specific
```listen_addresses = '*'```
Edit settings pg_hba.conf
```
sudo vi /etc/postgresql/<version>/main/pg_hba.conf
```
Modify the host configs, (split them with a tab
```
host    all             all             <IP>/32            md5
```

Modify UFW rules:
```
sudo ufw allow 5432/tcp
sudo ufw reload
```

Reboot the server (b/c sometimes restarting services doesn't do the job fully:
```
sudo shutdown -r now
```

# PG Admin (PSQL GUI)
```
curl https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo apt-key add -
sudo sh -c 'echo "deb https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'
sudo apt update
```
## Web Server
```
sudo apt install pgadmin4-web
sudo /usr/pgadmin4/bin/setup-web.sh
```
## Client 
```
sudo apt install pgadmin4-desktop
```

Modify UFW rules:
```
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw reload
```
