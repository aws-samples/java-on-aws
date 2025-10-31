-- Initialize travel database
-- This script is used by Testcontainers to set up the database for testing

-- Create travel_db (though Testcontainers will use the default database)
-- This is mainly for documentation and consistency with production setup

-- Verify database connection
SELECT 'Travel database initialized successfully' as status;