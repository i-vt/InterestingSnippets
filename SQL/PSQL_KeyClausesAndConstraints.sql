CREATE TABLE sample_table (
    -- Primary key: uniquely identifies each row
    id SERIAL PRIMARY KEY,

    -- Not null: column must have a value
    username VARCHAR(50) NOT NULL,

    -- Unique: prevents duplicate values in the column
    email VARCHAR(100) UNIQUE,

    -- Default: sets a default value if none is provided
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Check: enforces a condition on the column values
    age INT CHECK (age >= 18),

    -- Foreign key: enforces referential integrity with another table
    department_id INT REFERENCES departments(id),

    -- Multiple column primary key (alternative to SERIAL above)
    -- PRIMARY KEY (column1, column2)

    -- Foreign key with explicit constraint name and action
    manager_id INT,
    CONSTRAINT fk_manager FOREIGN KEY (manager_id)
        REFERENCES employees(id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    -- Unique constraint on multiple columns
    CONSTRAINT unique_user_email UNIQUE (username, email)
);
