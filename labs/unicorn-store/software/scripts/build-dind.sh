#bin/sh

docker network create dind-network

# Add to Dockerfile
# COPY src ./src/
# ENV DOCKER_HOST=tcp://dind:2375
# RUN mvn clean package && mv target/store-spring-1.0.0-exec.jar store-spring.jar

docker run --privileged -d --name dind -d -p 2375:2375 \
    --network dind-network --network-alias dind -e DOCKER_TLS_CERTDIR="" docker:dind

docker build --network=dind-network -t unicorn-store-spring:latest .

docker stop $(docker ps -a | grep "dind" | awk '{print $1}')
docker rm $(docker ps -a | grep "dind" | awk '{print $1}')
