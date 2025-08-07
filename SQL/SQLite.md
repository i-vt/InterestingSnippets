# SQLite

## Install
```
sudo apt update
sudo apt install sqlite3
```
## Connect to database
```
sqlite3 chatgpt_data.db
```

## Cheatsheet
```
-- Inside SQLite shell: (sqlite>)
.tables                     -- List all tables
.schema imported_data       -- View schema of the table
SELECT * FROM imported_data LIMIT 10; -- View first 10 rows
.quit                       -- Exit
```
