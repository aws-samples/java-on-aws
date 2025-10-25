-- Create ai_agent_db with pgvector extension
CREATE DATABASE ai_agent_db;
\c ai_agent_db;
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify vector extension is installed in ai_agent_db
\c ai_agent_db;
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Create backoffice_db
\c postgres;
CREATE DATABASE backoffice_db;

-- Create travel_db
CREATE DATABASE travel_db;

-- Verify databases were created
\l
