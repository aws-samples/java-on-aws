docker compose -f postgres-quarkus.yaml up

# docker build -t unicorn-store-quarkus:latest .

# export QUARKUS_DATASOURCE_JDBC_URL="jdbc:postgresql://localhost:5432/unicorns"
# export QUARKUS_DATASOURCE_PASSWORD="postgres"
# export QUARKUS_DATASOURCE_USERNAME="postgres"

# docker run --network host -p 8080:8080 unicorn-store-quarkus:latest -e QUARKUS_DATASOURCE_JDBC_URL=$QUARKUS_DATASOURCE_JDBC_URL -e QUARKUS_DATASOURCE_PASSWORD=$QUARKUS_DATASOURCE_PASSWORD -e QUARKUS_DATASOURCE_USERNAME=$QUARKUS_DATASOURCE_USERNAME

# mvn quarkus:dev

# mvn clean package
# java -jar ./target/quarkus-app/quarkus-run.jar
