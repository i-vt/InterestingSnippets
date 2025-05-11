CREATE TABLE all_data_types_demo (
    -- Numeric Types
    smallint_col SMALLINT,                     -- e.g., 32767
    integer_col INTEGER,                       -- e.g., 2147483647
    bigint_col BIGINT,                         -- e.g., 9223372036854775807
    decimal_col DECIMAL(10,2),                 -- e.g., 12345.67
    numeric_col NUMERIC(12,4),                 -- e.g., 98765.4321
    real_col REAL,                             -- e.g., 3.14
    double_precision_col DOUBLE PRECISION,     -- e.g., 3.14159265359
    serial_col SERIAL,                         -- e.g., auto-incrementing integer

    -- Monetary Type
    money_col MONEY,                           -- e.g., $123.45

    -- Character Types
    char_col CHAR(10),                         -- e.g., 'abc       '
    varchar_col VARCHAR(50),                   -- e.g., 'hello world'
    text_col TEXT,                             -- e.g., 'This is a long string.'

    -- Binary Data Type
    bytea_col BYTEA,                           -- e.g., E'\\xDEADBEEF'

    -- Date/Time Types
    timestamp_col TIMESTAMP,                   -- e.g., '2025-05-11 13:45:00'
    timestamptz_col TIMESTAMPTZ,               -- e.g., '2025-05-11 13:45:00+00'
    date_col DATE,                             -- e.g., '2025-05-11'
    time_col TIME,                             -- e.g., '13:45:00'
    timetz_col TIMETZ,                         -- e.g., '13:45:00+02'
    interval_col INTERVAL,                     -- e.g., '1 year 2 months 3 days'

    -- Boolean Type
    boolean_col BOOLEAN,                       -- e.g., TRUE

    -- UUID Type
    uuid_col UUID,                             -- e.g., '550e8400-e29b-41d4-a716-446655440000'

    -- Geometric Types
    point_col POINT,                           -- e.g., '(1.5,2.5)'
    line_col LINE,                             -- e.g., '{1,2,3}' (ax + by + c = 0)
    lseg_col LSEG,                             -- e.g., '[(0,0),(1,1)]'
    box_col BOX,                               -- e.g., '((1,1),(4,4))'
    path_col PATH,                             -- e.g., '[(1,1),(2,2),(3,1)]'
    polygon_col POLYGON,                       -- e.g., '((0,0),(4,0),(4,4),(0,4))'
    circle_col CIRCLE,                         -- e.g., '<(1,1),5>'

    -- Network Address Types
    cidr_col CIDR,                             -- e.g., '192.168.100.0/24'
    inet_col INET,                             -- e.g., '192.168.1.1'
    macaddr_col MACADDR,                       -- e.g., '08:00:2b:01:02:03'

    -- Bit String Types
    bit_col BIT(8),                            -- e.g., B'10101010'
    bit_varying_col BIT VARYING(16),           -- e.g., B'1101'

    -- Text Search Type
    tsvector_col TSVECTOR,                     -- e.g., 'fat:2,4 cat:3'
    tsquery_col TSQUERY,                       -- e.g., 'fat & cat'

    -- JSON Types
    json_col JSON,                             -- e.g., '{"name": "Alice", "age": 30}'
    jsonb_col JSONB,                           -- e.g., '{"name": "Bob", "active": true}'

    -- XML Type
    xml_col XML,                               -- e.g., '<note><to>Alice</to></note>'

    -- Array Type
    int_array_col INTEGER[],                   -- e.g., '{1,2,3,4,5}'

    -- Range Types
    int4range_col INT4RANGE,                   -- e.g., '[1,10)'
    numrange_col NUMRANGE,                     -- e.g., '[10.5,20.5]'
    tsrange_col TSRANGE,                       -- e.g., '[2025-01-01 00:00,2025-12-31 23:59)'
    tstzrange_col TSTZRANGE,                   -- e.g., '[2025-01-01 00:00+00,2025-12-31 23:59+00)'
    daterange_col DATERANGE                    -- e.g., '[2025-01-01,2025-12-31]'
);
