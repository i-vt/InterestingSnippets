-- 1. Rename a database
-- Note: You cannot rename the currently connected database
ALTER DATABASE old_db_name RENAME TO new_db_name;

-- 2. Change the owner of a database
-- Replace 'target_db' and 'new_owner' with actual names
ALTER DATABASE target_db OWNER TO new_owner;

-- 3. Set a connection limit
ALTER DATABASE target_db CONNECTION LIMIT 10;

-- 4. Set default configuration settings for a database
ALTER DATABASE target_db SET work_mem = '64MB';
ALTER DATABASE target_db SET maintenance_work_mem = '128MB';
ALTER DATABASE target_db SET timezone = 'UTC';

-- 5. Disallow connections (temporarily disable access)
-- Note: This will not disconnect current sessions
UPDATE pg_database SET datallowconn = false WHERE datname = 'target_db';

-- 6. Re-allow connections
UPDATE pg_database SET datallowconn = true WHERE datname = 'target_db';

-- 7. Terminate active connections to a database
-- Must be connected to a different database
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'target_db'
  AND pid <> pg_backend_pid();

-- 8. Drop a database safely
-- Cannot be connected to the target_db when running this
DROP DATABASE IF EXISTS target_db;

-- 9. List all non-template databases and their owners
SELECT datname AS database_name,
       datdba::regrole AS owner,
       pg_encoding_to_char(encoding) AS encoding,
       datcollate AS collation,
       datctype AS ctype
FROM pg_database
WHERE datistemplate = false;
