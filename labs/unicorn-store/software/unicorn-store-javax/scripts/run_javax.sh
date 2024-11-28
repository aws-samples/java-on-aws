# cd unicorn-store-javax

docker build --no-cache -f wildfly/Dockerfile -t unicorn-store-javax:latest . && \
docker compose -f wildfly/docker-compose.yml up
docker rm $(docker ps -a | grep "javax" | awk '{print $1}')
