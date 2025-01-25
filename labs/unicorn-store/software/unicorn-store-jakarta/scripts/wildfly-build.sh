# cd unicorn-store-jakarta

cp ./wildfly/pom.xml ./pom.xml
mv ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java.wf ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java
docker build -f wildfly/Dockerfile -t unicorn-store-wildfly:latest .
# --no-cache