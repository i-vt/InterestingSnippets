
### Basic setup

Download
```
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql postgresql-client
```

Enable it:
```
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
sudo vim /etc/postgresql/<version>/main/postgresql.conf
```
Change line to uncommented and replace localhost with a star or something more specific
```listen_addresses = '*'```
Edit settings pg_hba.conf
```
sudo nano /etc/postgresql/<version>/main/pg_hba.conf
```
Modify the host configs, (split them with a tab
```host    all             all             <IP>/32            md5```

Modify UFW rules:
```
sudo ufw allow 5432/tcp
sudo ufw reload
```

Reboot the server (b/c sometimes restarting services doesn't do the job fully:
```
sudo shutdown -r now
```
