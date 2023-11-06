
### Basic setup

Download
```
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql
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
```
