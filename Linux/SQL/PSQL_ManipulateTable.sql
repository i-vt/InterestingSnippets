-- Create a table
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    position TEXT,
    salary NUMERIC(10, 2),
    hire_date DATE
);

-- Alter the table
-- Add a new column
ALTER TABLE employees ADD COLUMN email TEXT;

-- Rename a column
ALTER TABLE employees RENAME COLUMN email TO contact_email;

-- Change column type
ALTER TABLE employees ALTER COLUMN salary TYPE MONEY;

-- Drop a column
ALTER TABLE employees DROP COLUMN position;

-- Rename the table
ALTER TABLE employees RENAME TO staff;

-- Insert, update, delete operations
-- Insert data
INSERT INTO staff (name, contact_email, salary, hire_date)
VALUES ('Alice Smith', 'alice@example.com', 55000.00, '2023-06-01');

-- Update data
UPDATE staff
SET salary = salary + 5000
WHERE name = 'Alice Smith';

-- Delete data
DELETE FROM staff
WHERE name = 'Alice Smith';

-- Select queries
-- Select all rows
SELECT * FROM staff;

-- Filtered select
SELECT name, salary FROM staff WHERE salary > 60000;

-- Truncate and drop
-- Remove all rows from the table
TRUNCATE TABLE staff;

-- Drop the table entirely
DROP TABLE staff;

-- Additional operations
-- Create a copy of the table structure without data
CREATE TABLE staff_copy (LIKE staff INCLUDING ALL);

-- Add a constraint
ALTER TABLE staff ADD CONSTRAINT salary_check CHECK (salary > 0);

-- Set a default value
ALTER TABLE staff ALTER COLUMN salary SET DEFAULT 30000;
