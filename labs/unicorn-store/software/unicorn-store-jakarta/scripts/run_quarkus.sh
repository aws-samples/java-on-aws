export QUARKUS_DATASOURCE_JDBC_URL="jdbc:postgresql://localhost:5432/unicorns"
export QUARKUS_DATASOURCE_PASSWORD="postgres"
export QUARKUS_DATASOURCE_USERNAME="postgres"

mvn quarkus:dev

# mvn clean package
# java -jar ./target/quarkus-app/quarkus-run.jar

# docker build --no-cache -t unicorn-store-quarkus:latest .
