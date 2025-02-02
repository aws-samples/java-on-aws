# cd unicorn-store-jakarta

docker compose -f wildfly/docker-compose.yml up
docker rm $(docker ps -a | grep "wildfly" | awk '{print $1}')
