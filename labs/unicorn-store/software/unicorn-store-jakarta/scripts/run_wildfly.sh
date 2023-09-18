# docker build --no-cache -t unicorn-spring:latest .

docker run --rm -p 8080:8080 -p 9990:9990 --name wildfly \
    -it unicorn-spring:latest \
    /opt/jboss/wildfly/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0

# mvn wildfly:execute-commands
# mvn clean package wildfly:deploy

# mvn clean package
# java -jar target/wildfly-bootable.jar --deployment=target/store-spring.war -b=0.0.0.0
