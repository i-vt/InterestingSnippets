# SQL 

## Create
Decimal 3 numbers 2 decimals
-9.99 min, 9.99 max
Optional parameters NOT NULL, and DEFAULT 1.00
```
CREATE TABLE products (
    price DECIMAL(3,2) NOT NULL DEFAULT 1.00
);
```

## Keys

```
CREATE TABLE users (
    user_id INT PRIMARY KEY,
    username VARCHAR(50)
);
```

```
-- Parent table
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name VARCHAR(100)
);

-- Child table
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    OrderDate DATE,
    CustomerID INT,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);
```

## Export PostgreSQL Schema to DBML

### Option 1: `dbml-cli` (Node.js CLI)

```
npm install -g dbml-cli

# Export PostgreSQL schema to SQL
pg_dump -U your_user -d your_db -s -f schema.sql

# Convert SQL to DBML
dbml-cli@2.3.0 sql2dbml schema.sql -o schema.dbml
```

### Option 2: dbdiagram.io (Web UI)

```
# Step 1: Export schema to SQL
pg_dump -U your_user -d your_db -s > schema.sql

# Step 2: Go to https://dbdiagram.io
# Step 3: Import > SQL and paste your schema
# Step 4: DBML output will be generated
```

### Option 3: pg-to-dbml (Python Script)

```
git clone https://github.com/Kononnable/pg-to-dbml.git
cd pg-to-dbml

pip install -r requirements.txt

python pg_to_dbml.py --database your_db --user your_user --host localhost --port 5432
```

### Option 4: pgModeler (Desktop GUI)

```
# Step 1: Download pgModeler: https://pgmodeler.io/download
# Step 2: Connect to your PostgreSQL database
# Step 3: Export model to SQL
# Step 4: Convert SQL to DBML using dbml-cli or dbdiagram.io
```

### Composite Keys
|   Benefit                           | Description                                                                                           |
|-------------------------------------|-------------------------------------------------------------------------------------------------------|
| Enforces multi-column uniqueness    | A student can enroll in multiple courses, but only once per course. Use `(student_id, course_id)` to enforce this. |
| Models real-world relationships     | Many real-world identifiers are not just one field — e.g., `(order_id, product_id)` in an order system. |
| Supports proper foreign key relationships | Allows other tables to reference **combinations** of keys, not just single columns.         |
| Avoids surrogate-only design        | Not every situation needs an artificial `id`; composite keys often reflect **real, natural uniqueness**. |

```
CREATE TABLE orders (
    order_id INT,
    product_id INT,
    PRIMARY KEY (order_id, product_id)
);
```

### Unique key
```
CREATE TABLE users (
    email VARCHAR(100) UNIQUE
);
```

### Foreign Key
```
CREATE TABLE orders (
    customer_id INT REFERENCES customers(customer_id)
);
```

## Alter
```
-- Add PRIMARY KEY
ALTER TABLE users ADD PRIMARY KEY (user_id);

-- Add UNIQUE constraint
ALTER TABLE users ADD UNIQUE (email);

-- Add FOREIGN KEY
ALTER TABLE orders
ADD CONSTRAINT fk_customer
FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
```

Mysql
```
ALTER TABLE example_table
CHANGE old_column1 new_column1 DATA_TYPE,
CHANGE old_column2 new_column2 DATA_TYPE;
```
## Table Creation Rules

1. What is one thing that your table describes?
2. How will you get at that one thing? (easy to query design)
3. Do your columns contain atomic data to make your queries short and to the point?
4. Preferably avoid duplicate data

| Column Purpose     |   Not Atomic (Bad)          |   Atomic (Good)     |
|--------------------|------------------------------|----------------------|
| Fruits List        | 'apple, banana, orange'      | 'apple'              |
| Full Name          | 'John & Jane'                | 'John'               |
| Tags (as JSON)     | '["tag1", "tag2"]'           | 'tag1'               |
| Phone Numbers      | '123-4567, 234-5678'          | '123-4567'           |
| Address Components | '123 Main St, NY, 10001'      | '123 Main St'        |


## Insert
```
CREATE TABLE users (
    user_id INT,
    username VARCHAR(50),
    signup_date DATE,
    is_active BOOLEAN
);

INSERT INTO users (user_id, username, signup_date, is_active)
VALUES
    (1, 'johndoe', '2025-07-10', TRUE),
    (2, 'janedoe', '2025-07-09', FALSE),
    (3, 'alexsmith', '2025-07-08', TRUE);
```

## Select
```
SELECT row_one, row2 FROM table_somethings
WHERE
row3 = 40
AND
row4 = 'Bee \' bus';
```
## Update
```
-- Update one user's info
UPDATE users
SET username = 'newname', is_active = FALSE
WHERE user_id = 3;
```

## Delete 
```
DELETE FROM fruits
WHERE fruit_name ILIKE 'ap%';
```

## Debugging
`show warnings;`


## Wrong

42 will always be true so you'll get the full table
```
SELECT * FROM table_shits WHERE row3 = 41 AND 42;
```

```
SELECT * FROM products
WHERE price > 1.00 AND price <= 9.99;
```

'L' includes all strings that start with 'L' or any letter after it (e.g., 'M', 'Pepsi', 'Zest').
Example Matches: 'Latte', 'Lemonade', 'Milk', 'Sprite', 'Zinger'; 
Example Non-Matches: 'Apple Juice', 'Coca-Cola', 'Fanta'.
```
SELECT * FROM drinks WHERE drink_name >= 'L';
```

### Comparison
| Comparator   | Description                          | Example                          |
|--------------|--------------------------------------|----------------------------------|
| `=`          | Equal to                             | `price = 1.00`                   |
| `<>` or `!=` | Not equal to                         | `price <> 1.00` or `price != 1.00` |
| `>`          | Greater than                         | `price > 1.00`                   |
| `<`          | Less than                            | `price < 1.00`                   |
| `>=`         | Greater than or equal to             | `price >= 1.00`                  |
| `<=`         | Less than or equal to                | `price <= 1.00`                  |
| `BETWEEN`    | Within a range (inclusive)           | `price BETWEEN 1.00 AND 5.00`   |
| `IN`         | Matches any in a list                | `price IN (1.00, 2.00, 3.00)`   |
| `NOT IN`     | Does not match any in a list         | `price NOT IN (2.00, 3.00)`     |
| `IS NULL`    | Is null (no value)                   | `price IS NULL`                 |
| `IS NOT NULL`| Is not null                          | `price IS NOT NULL`             |

### Logical Operators
| Operator | Description                                 | Example                             |
|----------|---------------------------------------------|-------------------------------------|
| AND      | True if both conditions are true            | `price > 5 AND stock > 0`           |
| OR       | True if at least one condition is true      | `price < 5 OR stock > 10`           |
| NOT      | Reverses the condition                      | `NOT (price > 10)` or `NOT IN (...)`|

### Clauses
```
SELECT *
FROM products
WHERE
  NOT (category = 'Beverages')
  AND price > ALL (SELECT price FROM products WHERE category = 'Snacks')
  AND stock < ANY (SELECT stock FROM products WHERE discontinued = FALSE)
  AND discount > SOME (SELECT discount FROM promotions WHERE active = TRUE);
```
- `NOT (category = 'Beverages')`: Excludes beverages.
- `price > ALL (...)`: Only includes products priced higher than every snack.
- `stock < ANY (...)`: Includes products with stock less than at least one active product.
- `discount > SOME (...)`: Includes products with a discount greater than at least one active promotion.


| Clause      | Description                          | Example                               |
|-------------|--------------------------------------|---------------------------------------|
| EXISTS      | Checks if subquery returns results   | `WHERE EXISTS (SELECT * FROM...)`     |
| NOT EXISTS  | Opposite of EXISTS                   | `WHERE NOT EXISTS (...)`              |
| ALL         | True if comparison is true for all   | `price > ALL (SELECT price FROM...)`  |
| ANY / SOME  | True if true for **any** value       | `price < ANY (SELECT price FROM...)`  |

## LIKE
| Pattern        | Description                                       | Example Match          | Works With |
|----------------|---------------------------------------------------|------------------------|------------|
| `'A%'`         | Starts with "A"                                   | `'Apple'`, `'Almond'`  | LIKE, ILIKE|
| `'%e'`         | Ends with "e"                                     | `'Orange'`, `'Pine'`   | LIKE, ILIKE|
| `'%in%'`       | Contains "in" anywhere                            | `'Wine'`, `'Pineapple'`| LIKE, ILIKE|
| `'A_B'`        | "A", any one char, then "B"                       | `'ACB'`, `'A1B'`       | LIKE, ILIKE|
| `'A__B'`       | "A", any two chars, then "B"                      | `'AXYB'`, `'A12B'`     | LIKE, ILIKE|
| `'100\%%'`     | Escapes `%` to match a literal percent symbol     | `'100% off'`           | LIKE (with ESCAPE) |
| `'_'`          | Matches exactly one character                     | `'A'`, `'B'` (1 char)  | LIKE, ILIKE|

| Operator | Case Sensitivity | Notes                              |
|----------|------------------|------------------------------------|
| `LIKE`   | Case-sensitive   | `'apple' LIKE 'A%'` -> No Match    |
| `ILIKE`  | Case-insensitive | `'apple' ILIKE 'A%'` -> Match      |

### Data types
| Data Type       | Description                                    | Example Values               | Notes                                             |
|------------------|------------------------------------------------|------------------------------|---------------------------------------------------|
| `INT` / `INTEGER`| Whole numbers                                  | `1`, `-50`, `1000`           | Common for IDs, counts                            |
| `SMALLINT`       | Smaller range of integers                      | `-32,768` to `32,767`        | Saves space                                       |
| `BIGINT`         | Very large integers                            | Larger than 2 billion        | For large IDs or counts                           |
| `DECIMAL(p,s)`   | Fixed-point number                             | `DECIMAL(5,2)` → `123.45`    | Precision-safe for currency                       |
| `NUMERIC(p,s)`   | Same as `DECIMAL`                              |                              | Fully ANSI-compliant                              |
| `FLOAT`          | Approximate floating-point number              | `3.14`, `0.0001`             | May lose precision                                |
| `REAL`           | Single-precision float                         |                              | Less precise than `FLOAT`                         |
| `CHAR(n)`        | Fixed-length string                            | `'YES  '` (padded to 5 chars)| Padded with spaces                                |
| `VARCHAR(n)`     | Variable-length string                         | `'Hello'`                    | Most commonly used for text                       |
| `TEXT`           | Large/unlimited text                           | Long articles, descriptions  | No length limit in some DBs (e.g., PostgreSQL)    |
| `DATE`           | Calendar date                                  | `2025-07-10`                 | Year-month-day format                             |
| `TIME`           | Time of day                                    | `14:30:00`                   | No date part                                      |
| `TIMESTAMP`      | Date + time                                    | `2025-07-10 14:30:00`        | Used for logs, updates                            |
| `BOOLEAN`        | True/false                                     | `TRUE`, `FALSE`, `0`, `1`    | MySQL uses `TINYINT(1)` to simulate               |
| `BLOB`           | Binary large object                            | Images, files                | Binary data (not readable as text)                |

## String Manipulation

`SELECT SUBSTRING(TRIM(REPLACE('  abc-def  ', '-', '_')) FROM 1 FOR 5) AS cleaned_string;`

```
cleaned_string
--------------
abc_d
```

Normalize data to group duplicates:
```
SELECT LOWER(TRIM(name)) AS normalized_name, COUNT(*) 
FROM employees
GROUP BY normalized_name;
```

### Core Substring Functions

| Function | Description | Example |
|----------|-------------|---------|
| `SUBSTRING(str FROM start FOR length)` or `SUBSTRING(str, start, length)` | Extracts part of a string | `SUBSTRING('abcdef', 2, 3)` → `'bcd'` |
| `LEFT(str, n)` | Gets the leftmost `n` characters | `LEFT('abcdef', 3)` → `'abc'` |
| `RIGHT(str, n)` | Gets the rightmost `n` characters | `RIGHT('abcdef', 2)` → `'ef'` |
| `MID(str, start, length)` | Alias for `SUBSTRING()` (MySQL) | `MID('abcdef', 2, 3)` → `'bcd'` |

---

### Trimming and Padding

| Function | Description | Example |
|----------|-------------|---------|
| `TRIM(str)` | Removes leading and trailing spaces | `TRIM(' abc ')` → `'abc'` |
| `LTRIM(str)` | Removes leading spaces | `LTRIM(' abc')` → `'abc'` |
| `RTRIM(str)` | Removes trailing spaces | `RTRIM('abc ')` → `'abc'` |
| `LPAD(str, length, pad_str)` | Left-pads a string to a certain length | `LPAD('abc', 5, '0')` → `'00abc'` |
| `RPAD(str, length, pad_str)` | Right-pads a string | `RPAD('abc', 5, 'x')` → `'abcxx'` |

---

### Search and Replace

| Function | Description | Example |
|----------|-------------|---------|
| `INSTR(str, substr)` (MySQL) / `POSITION(substr IN str)` (PostgreSQL) | Finds position of substring | `INSTR('hello', 'e')` → `2` |
| `CHARINDEX(substr, str)` (SQL Server) | Same as above | `CHARINDEX('e', 'hello')` → `2` |
| `REPLACE(str, from_str, to_str)` | Replaces all occurrences | `REPLACE('a-b-c', '-', '+')` → `'a+b+c'` |
| `REGEXP_REPLACE(str, pattern, replacement)` | Regex-based replacement (PostgreSQL, MySQL 8+) | `REGEXP_REPLACE('abc123', '\\d+', '')` → `'abc'` |

---

### String Length

| Function | Description | Example |
|----------|-------------|---------|
| `LENGTH(str)` | Number of bytes (MySQL, SQLite) | `LENGTH('abc')` → `3` |
| `CHAR_LENGTH(str)` | Number of characters | `CHAR_LENGTH('abc')` → `3` |


## Case

Also works with update
``` 
SELECT
  order_id,
  status_code,
  CASE
    WHEN status_code = 1 THEN 'Pending'
    WHEN status_code = 2 THEN 'Shipped'
    WHEN status_code = 3 THEN 'Delivered'
    WHEN status_code = 4 THEN 'Cancelled'
    ELSE 'Unknown'
  END AS status_description
FROM orders;
```

## Order By

Default is ascending: In most databases, when sorting ascending, NULL values appear first.

| Syntax/Option           | Description                                               | Example                                                       |
|-------------------------|-----------------------------------------------------------|---------------------------------------------------------------|
| `ORDER BY col ASC`      | Sort by column ascending (default)                        | `ORDER BY name ASC`                                           |
| `ORDER BY col DESC`     | Sort by column descending                                 | `ORDER BY salary DESC`                                        |
| Multiple Columns        | Sort by multiple columns                                  | `ORDER BY last_name, first_name DESC`                         |
| Expressions             | Sort by computed values or expressions                    | `ORDER BY price * quantity DESC`                              |
| Aliases                 | Use alias from SELECT in sorting                          | `SELECT salary * 1.1 AS adjusted_salary ... ORDER BY adjusted_salary` |
| Column Position         | Sort by column position (1-based)                         | `ORDER BY 2` (sorts by the second column in SELECT)           |
| `CASE` Statement        | Custom sort order with logic                              | `ORDER BY CASE status WHEN 'urgent' THEN 1 ... END`           |
| `NULLS FIRST/LAST`      | Control sort order of NULLs (dialect-dependent)           | `ORDER BY due_date ASC NULLS LAST`                            |

```
SELECT name, age FROM users
ORDER BY column_name ASC NULLS LAST;
```


## Aggregate Functions
| Function                      | Description                                       | Example                          |
|------------------------------|---------------------------------------------------|----------------------------------|
| `SUM(col)`                   | Total of numeric values                           | `SUM(salary)`                    |
| `AVG(col)`                   | Average (mean) value                              | `AVG(score)`                     |
| `MIN(col)`                   | Minimum value                                     | `MIN(age)`                       |
| `MAX(col)`                   | Maximum value                                     | `MAX(price)`                     |
| `COUNT(*)`                   | Count all rows                                    | `COUNT(*)`                       |
| `COUNT(col)`                 | Count non-NULL values in a column                 | `COUNT(email)`                   |
| `GROUP_CONCAT(col)`          | Concatenate values into a string (MySQL)          | `GROUP_CONCAT(name)`             |
| `STRING_AGG(col, ', ')`      | Concatenate values into a string (PostgreSQL)     | `STRING_AGG(name, ', ')`         |
| `VAR_SAMP(col)`              | Sample variance (PostgreSQL, etc.)                | `VAR_SAMP(salary)`               |
| `VARIANCE(col)`              | Population variance (some databases)              | `VARIANCE(salary)`               |
| `STDDEV_SAMP(col)`           | Sample standard deviation                         | `STDDEV_SAMP(score)`             |
| `STDDEV(col)`                | Standard deviation (alias in some databases)      | `STDDEV(salary)`                 |

## Counters / Limits

| Function / Clause           | Description                                        | SQL Dialect           | Example                            |
|----------------------------|----------------------------------------------------|------------------------|------------------------------------|
| `LIMIT n`                  | Return first `n` rows                              | MySQL, PostgreSQL      | `SELECT * FROM users LIMIT 10`     |
| `LIMIT n OFFSET m`         | Skip `m` rows, then return `n` rows               | MySQL, PostgreSQL      | `SELECT * FROM users LIMIT 5 OFFSET 10` |
| `TOP n`                    | Return first `n` rows                              | SQL Server             | `SELECT TOP 5 * FROM users`        |
| `FETCH FIRST n ROWS ONLY`  | ANSI standard for limiting rows                    | PostgreSQL, Oracle     | `SELECT * FROM users FETCH FIRST 10 ROWS ONLY` |
| `OFFSET m ROWS FETCH NEXT n ROWS ONLY` | Skip `m`, then return `n` rows        | SQL Server, Oracle     | `SELECT * FROM users OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY` |
| `ROWNUM`                   | Pseudocolumn for limiting rows                     | Oracle (legacy)        | `SELECT * FROM users WHERE ROWNUM <= 5` |
| `ROW_NUMBER()`             | Assigns row number (useful for pagination)         | All (window function)  | `SELECT * FROM (SELECT *, ROW_NUMBER() OVER (...) AS rn FROM users) WHERE rn BETWEEN 11 AND 20` |

## (n)NF
| Normal Form | Key Rule                                                      |
| ----------- | ------------------------------------------------------------- |
| **1NF**     | Atomic columns (no repeating groups)                          |
| **2NF**     | No partial dependency on part of a composite key              |
| **3NF**     | No transitive dependency (non-key depends on another non-key) |

### 1 NF
StudentID | Name    | Courses
----------|---------|----------------
1         | Alice   | Math, Physics

StudentID | Name    | Course
----------|---------|--------
1         | Alice   | Math
1         | Alice   | Physics



### 2 NF
All non-key attributes must be fully dependent on the entire primary key (no partial dependency)


### 3 NF
```
From this:

StudentID | StudentName | Department | DepartmentHead


Split into this: 

Table: Student
StudentID | StudentName | Department

Table: Department
Department | DepartmentHead
```

## Group By
```
SELECT Region, SUM(Amount) AS TotalSales
FROM Sales
GROUP BY Region;
```
| Region | TotalSales |
| ------ | ---------- |
| East   | 300        |
| West   | 250        |
| North  | 300        |

| SQL Operation  | Purpose                                      | Key Rule / Usage Example                                  |
|----------------|----------------------------------------------|------------------------------------------------------------|
| `UNION`        | Combines rows from two queries, **removes duplicates** | `SELECT col FROM table1 UNION SELECT col FROM table2;`    |
| `UNION ALL`    | Combines rows, **includes duplicates**        | `SELECT col FROM table1 UNION ALL SELECT col FROM table2;`|
| `INTERSECT`    | Returns only rows that appear in **both** queries | `SELECT col FROM table1 INTERSECT SELECT col FROM table2;`|
| `EXCEPT`       | Returns rows from the first query **not in** the second | `SELECT col FROM table1 EXCEPT SELECT col FROM table2;`   |
| `INNER JOIN`   | Returns rows with **matching values in both tables** | `SELECT * FROM A INNER JOIN B ON A.id = B.id;`            |
| `LEFT JOIN`    | All rows from left table, **matched or not** in right | `SELECT * FROM A LEFT JOIN B ON A.id = B.id;`             |
| `RIGHT JOIN`   | All rows from right table, **matched or not** in left | `SELECT * FROM A RIGHT JOIN B ON A.id = B.id;`            |
| `FULL JOIN`    | All rows from **both** tables, matched or not | `SELECT * FROM A FULL JOIN B ON A.id = B.id;`             |
| `CROSS JOIN`   | **Cartesian product** of both tables          | `SELECT * FROM A CROSS JOIN B;`                           |
| `SELF JOIN`    | Join a table with **itself**                  | `SELECT A.name, B.name FROM Employees A JOIN Employees B ON A.manager_id = B.id;` |


```
SELECT Customers.Name, Orders.Amount
FROM Customers
INNER JOIN Orders ON Customers.CustomerID = Orders.CustomerID;
```
| OrderID | CustomerID | Amount |
| ------- | ---------- | ------ |
| 101     | 1          | 250    |
| 102     | 2          | 300    |
| 103     | 1          | 150    |
| 104     | 4          | 200    |

| CustomerID | Name  | City     |
| ---------- | ----- | -------- |
| 1          | Alice | London   |
| 2          | Bob   | New York |
| 3          | Carol | Paris    |

creates this:
| Name  | Amount |
| ----- | ------ |
| Alice | 250    |
| Bob   | 300    |
| Alice | 150    |

## Check constraints
```
CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    age INT CHECK (age >= 18),
    salary DECIMAL(10,2) DEFAULT 30000 CHECK (salary > 0),
    email VARCHAR(255) UNIQUE
);
```

```
CREATE TABLE employees (
    id INT,
    age INT,
    salary DECIMAL(10, 2),

    CONSTRAINT chk_age CHECK (age >= 18),
    CONSTRAINT chk_salary CHECK (salary > 0)
);
```

| Feature           | `CHECK`                                           | `CONSTRAINT`                                     |
| ----------------- | ------------------------------------------------- | ------------------------------------------------ |
| **What it is**    | A *type* of constraint                            | A *keyword* used to define and name constraints  |
| **Purpose**       | Validates that a column’s value meets a condition | Used to apply rules like `CHECK`, `UNIQUE`, etc. |
| **Usage**         | Can be used directly or with `CONSTRAINT`         | Used to *name* and apply any constraint          |
| **Can be named?** | Not unless used with `CONSTRAINT` keyword         | Yes, always involves naming                      |
| **Example**       | `CHECK (age > 18)`                                | `CONSTRAINT chk_age CHECK (age > 18)`            |


## View
```
CREATE VIEW active_customers AS
SELECT id, name, email
FROM customers
WHERE status = 'active';
```

A saved SQL query that you can treat like a table.

| Use Case                     | Explanation                                                           |
| ---------------------------- | --------------------------------------------------------------------- |
| **Simplify complex queries** | Write a complex JOIN or filter once, reuse it like a table            |
| **Restrict access**          | Show only specific columns or rows to users                           |
| **Abstract business logic**  | Hide raw table structure; show calculated or renamed columns          |
| **Maintain consistency**     | Centralize logic so it updates automatically when source data changes |

## Privileges
| Privilege        | Description                            |
| ---------------- | -------------------------------------- |
| `SELECT`         | Read data from tables or views         |
| `INSERT`         | Add new records                        |
| `UPDATE`         | Modify existing records                |
| `DELETE`         | Remove records                         |
| `CREATE`         | Create new tables, views, or databases |
| `DROP`           | Delete tables or databases             |
| `ALTER`          | Modify table structure                 |
| `INDEX`          | Create or remove indexes               |
| `EXECUTE`        | Run stored procedures/functions        |
| `ALL PRIVILEGES` | Grants all of the above                |


```
-- Create a role
CREATE ROLE reporting_user;

-- Grant privileges to the role
GRANT SELECT ON reports.* TO reporting_user;

-- Assign role to user
GRANT reporting_user TO 'bob'@'localhost';

REVOKE INSERT, UPDATE ON sales.customers FROM 'alice'@'localhost';
```

```
GRANT role_name TO username;
REVOKE role_name FROM username;
REVOKE SELECT ON mydb.* FROM 'app_reader';
```

## To Do

### Read List
- SQL Antipatterns: Avoiding the Pitfalls of Database Programming (Pragmatic Programmers)

### Software
https://dbeaver.io/download/ DBeaver Community is a free cross-platform database tool for developers, database administrators, analysts, and everyone working with data. It supports all popular SQL databases like MySQL, MariaDB, PostgreSQL, SQLite, Apache Family, and more.
https://dbdiagram.io/d

