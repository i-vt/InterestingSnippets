package main

import (
	"bufio"
	"database/sql"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	_ "github.com/mattn/go-sqlite3"
	"github.com/cheggaaa/pb/v3"
	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/transform"
)

const (
	txtFilePath   = "employee_id.txt"
	sqliteDBPath  = "employee_id.db"
	tableName     = "people"
	delimiter     = ','
	chunkSize     = 3000
)

func main() {
	// Check file existence
	if _, err := os.Stat(txtFilePath); os.IsNotExist(err) {
		log.Fatalf("❌ File not found: %s", txtFilePath)
	}

	// Remove old DB if exists
	if _, err := os.Stat(sqliteDBPath); err == nil {
		os.Remove(sqliteDBPath)
	}

	// Get file size for progress
	info, err := os.Stat(txtFilePath)
	if err != nil {
		log.Fatal(err)
	}
	fileSize := info.Size()

	// Connect to SQLite and optimize
	db, err := sql.Open("sqlite3", sqliteDBPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	_, err = db.Exec(`
		PRAGMA journal_mode = OFF;
		PRAGMA synchronous = OFF;
		PRAGMA temp_store = MEMORY;
		PRAGMA locking_mode = EXCLUSIVE;
	`)
	if err != nil {
		log.Fatal(err)
	}

	// Open file with cp1252 decoder
	rawFile, err := os.Open(txtFilePath)
	if err != nil {
		log.Fatal(err)
	}
	defer rawFile.Close()

	decoder := transform.NewReader(rawFile, charmap.Windows1252.NewDecoder())
	buffered := bufio.NewReader(decoder)

	// Read header
	headerLine, err := buffered.ReadString('\n')
	if err != nil {
		log.Fatal("❌ Could not read header line:", err)
	}
	columns := strings.Split(strings.TrimSpace(headerLine), string(delimiter))

	// Create table
	createTableSQL := buildCreateTableSQL(columns)
	_, err = db.Exec(createTableSQL)
	if err != nil {
		log.Fatalf("❌ Failed to create table: %v", err)
	}

	// Reset file to beginning
	rawFile.Seek(0, 0)
	decoder = transform.NewReader(rawFile, charmap.Windows1252.NewDecoder())
	csvReader := csv.NewReader(decoder)
	csvReader.Comma = delimiter
	csvReader.FieldsPerRecord = len(columns)

	// Skip header
	_, _ = csvReader.Read()

	// Start progress bar
	bar := pb.Full.Start64(fileSize)
	defer bar.Finish()

	var records [][]string
	count := 0

	for {
		record, err := csvReader.Read()
		if err == io.EOF {
			if len(records) > 0 {
				insertChunk(db, records, columns)
			}
			break
		}
		if err != nil {
			continue // skip bad line
		}

		for i := range record {
			record[i] = strings.TrimSpace(record[i])
		}

		records = append(records, record)
		count++

		if count%chunkSize == 0 {
			insertChunk(db, records, columns)
			records = [][]string{}
		}

		bar.Add(len(strings.Join(record, string(delimiter))) + 1) // Approx
	}

	fmt.Println("🔧 Creating indexes...")
	createIndexes(db)
	fmt.Printf("🎉 Done! SQLite DB '%s' is ready.\n", sqliteDBPath)
}

func buildCreateTableSQL(columns []string) string {
	var colDefs []string
	for _, col := range columns {
		colDefs = append(colDefs, fmt.Sprintf("\"%s\" TEXT", col))
	}
	return fmt.Sprintf("CREATE TABLE %s (%s);", tableName, strings.Join(colDefs, ", "))
}

func insertChunk(db *sql.DB, data [][]string, columns []string) {
	tx, err := db.Begin()
	if err != nil {
		log.Fatal(err)
	}

	colPlaceholders := strings.Repeat("?,", len(columns))
	colPlaceholders = colPlaceholders[:len(colPlaceholders)-1]
	insertSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s);",
		tableName,
		strings.Join(columns, ", "),
		colPlaceholders)

	stmt, err := tx.Prepare(insertSQL)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	for _, row := range data {
		vals := make([]interface{}, len(row))
		for i, v := range row {
			vals[i] = v
		}
		_, err := stmt.Exec(vals...)
		if err != nil {
			log.Println("❌ Failed insert:", err)
		}
	}
	tx.Commit()
}

func createIndexes(db *sql.DB) {
	indexes := []string{
		"CREATE INDEX IF NOT EXISTS idx_employee_id        ON people (employee_id);",
		"CREATE INDEX IF NOT EXISTS idx_firstname  ON people (firstname);",
		"CREATE INDEX IF NOT EXISTS idx_lastname   ON people (lastname);",
		"CREATE INDEX IF NOT EXISTS idx_aka1       ON people (aka1fullname);",
		"CREATE INDEX IF NOT EXISTS idx_dob        ON people (dob);",
		"CREATE INDEX IF NOT EXISTS idx_city       ON people (city);",
		"CREATE INDEX IF NOT EXISTS idx_zip        ON people (zip);",
	}

	for _, stmt := range indexes {
		_, err := db.Exec(stmt)
		if err != nil {
			log.Printf("❌ Index failed: %v", err)
		}
	}
	fmt.Println("✅ Indexes created.")
}
