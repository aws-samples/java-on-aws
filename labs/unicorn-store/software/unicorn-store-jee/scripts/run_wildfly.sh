mvn clean package
java -jar target/wildfly-bootable.jar --deployment=target/unicorn-store.war -b=0.0.0.0
