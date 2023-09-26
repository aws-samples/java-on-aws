export QUARKUS_DATASOURCE_JDBC_URL="jdbc:postgresql://localhost:5432/unicorns"
export QUARKUS_DATASOURCE_PASSWORD="postgres"

mvn quarkus:dev

# docker build --no-cache -t unicorn-store-quarkus:latest .
