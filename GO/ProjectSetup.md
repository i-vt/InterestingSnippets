# Setup GO project

## Linux

### Create Project Folder
```
mkdir csv_to_sqlite_importer
cd csv_to_sqlite_importer
```

### Initialize

```
go mod init csv_to_sqlite_importer
```

### Add Dependencies Needed

```
go get github.com/mattn/go-sqlite3
go get github.com/schollz/progressbar/v3
```

### Run

```
go run main.go
```
