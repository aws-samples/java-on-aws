#!/bin/bash

echo "🐘 Starting PostgreSQL + pgAdmin for Spring AI Application..."
echo ""
echo "📊 PostgreSQL Database (with pgvector extension):"
echo "  Databases: ai_agent_db (with pgvector), backoffice_db, travel_db"
echo "  Username: postgres"
echo "  Password: postgres"
echo "  Port: 5432"
echo "  Extensions: vector (pgvector) installed in ai_agent_db"
echo ""
echo "🌐 pgAdmin Web Interface:"
echo "  URL: http://localhost:8090"
echo "  Login: admin@admin.com / admin"
echo "  All 3 databases will be auto-configured!"
echo ""
echo "Press Ctrl+C to stop and remove containers"
echo ""

# Start PostgreSQL and pgAdmin in foreground mode
# When Ctrl+C is pressed, containers will be stopped and removed
docker-compose up --remove-orphans

echo ""
echo "🧹 Cleaning up containers..."
docker-compose down --volumes --remove-orphans
echo "✅ PostgreSQL and pgAdmin stopped and containers removed"
