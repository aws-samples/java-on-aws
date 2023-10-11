# cd unicorn-store-jakarta

mv ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java.wf ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java
docker build --no-cache -f wildfly/Dockerfile -t unicorn-store-wildfly:latest .
docker compose -f wildfly/docker-compose.yml up
docker rm $(docker ps -a | grep "wildfly" | awk '{print $1}')

# docker run --rm -p 8080:8080 -p 9990:9990 --name wildfly \
#     -it unicorn-store-wildfly:latest

# mvn wildfly:execute-commands
# mvn clean package wildfly:deploy
