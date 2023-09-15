mvn clean package
java -jar target/wildfly-bootable.jar --deployment=target/store-spring.war -b=0.0.0.0
