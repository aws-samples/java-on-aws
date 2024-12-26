# cd unicorn-store-spring

docker buildx build --load -t unicorn-store-spring:latest .
docker compose -f docker-compose.yml up
docker rm $(docker ps -a | grep "spring" | awk '{print $1}')
