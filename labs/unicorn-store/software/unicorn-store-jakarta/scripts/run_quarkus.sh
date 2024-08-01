# cd unicorn-store-jakarta

mv ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java.wf
cp ./quarkus/pom.xml ./pom.xml
docker build --no-cache -f quarkus/Dockerfile -t unicorn-store-quarkus:latest .
docker compose -f quarkus/docker-compose.yml up
docker rm $(docker ps -a | grep "quarkus" | awk '{print $1}')
rm ./pom.xml

# docker build -t unicorn-store-quarkus:latest .

# export QUARKUS_DATASOURCE_JDBC_URL="jdbc:postgresql://localhost:5432/unicorns"
# export QUARKUS_DATASOURCE_PASSWORD="postgres"
# export QUARKUS_DATASOURCE_USERNAME="postgres"

# docker run -p 8080:8080 unicorn-store-quarkus:latest -e QUARKUS_DATASOURCE_JDBC_URL=$QUARKUS_DATASOURCE_JDBC_URL -e QUARKUS_DATASOURCE_PASSWORD=$QUARKUS_DATASOURCE_PASSWORD -e QUARKUS_DATASOURCE_USERNAME=$QUARKUS_DATASOURCE_USERNAME

# mvn quarkus:dev
