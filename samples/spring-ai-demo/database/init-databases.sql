-- Create assistant_db with pgvector extension
CREATE DATABASE assistant_db;
\c assistant_db;
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify vector extension is installed in assistant_db
\c assistant_db;
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Create backoffice_db
\c postgres;
CREATE DATABASE backoffice_db;

-- Create travel_db
CREATE DATABASE travel_db;

-- Verify databases were created
\l
