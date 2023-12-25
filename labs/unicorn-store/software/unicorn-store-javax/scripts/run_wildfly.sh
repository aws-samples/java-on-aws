# cd unicorn-store-javax

docker build --no-cache -f wildfly/Dockerfile -t unicorn-store-wildfly:latest .
docker compose -f wildfly/docker-compose.yml up
docker rm $(docker ps -a | grep "wildfly" | awk '{print $1}')
