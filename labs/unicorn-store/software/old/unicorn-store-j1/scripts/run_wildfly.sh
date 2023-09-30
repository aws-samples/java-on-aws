mvn clean package
java -jar target/wildfly-bootable.jar --deployment=target/store-jee.war -b=0.0.0.0
