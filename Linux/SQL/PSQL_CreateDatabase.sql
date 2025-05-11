-- Basic database
CREATE DATABASE basic_db;

-- Database with a specific owner
CREATE DATABASE owned_db
    OWNER some_user;  -- Replace 'some_user' with an existing role

-- Database with a specific encoding
CREATE DATABASE utf8_db
    ENCODING 'UTF8';

-- Database with SQL_ASCII encoding (not recommended, but supported)
CREATE DATABASE ascii_db
    ENCODING 'SQL_ASCII';

-- Database using a specific locale
CREATE DATABASE locale_en_us
    LC_COLLATE='en_US.UTF-8'
    LC_CTYPE='en_US.UTF-8'
    ENCODING='UTF8'
    TEMPLATE=template0;

-- Database based on a template (copying structure/data from another database)
CREATE DATABASE cloned_db
    TEMPLATE basic_db;

-- Database with a specific tablespace (if tablespace exists)
CREATE DATABASE tablespace_db
    TABLESPACE pg_default;

-- Database with a connection limit
CREATE DATABASE limited_db
    CONNECTION LIMIT 5;
