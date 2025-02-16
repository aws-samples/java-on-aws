# cd unicorn-store-javax
docker build -t unicorn-store-javax:latest . && \
docker compose up
docker rm $(docker ps -a | grep "javax" | awk '{print $1}')
