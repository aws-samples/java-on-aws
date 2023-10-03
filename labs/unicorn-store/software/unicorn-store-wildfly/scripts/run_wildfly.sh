docker build --no-cache -t unicorn-store-wildfly:latest . && docker compose up && docker rm $(docker ps -aq)

# docker build --no-cache -t unicorn-store:latest .

# docker run --rm -p 8080:8080 -p 9990:9990 --name wildfly \
#     -it unicorn-store:latest \
#     /opt/jboss/wildfly/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0

# mvn wildfly:execute-commands
# mvn clean package wildfly:deploy
