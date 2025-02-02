# cd unicorn-store-jakarta

mv ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java ./src/main/java/com/unicorn/store/data/EntityManagerProducer.java.wf
cp ./quarkus/pom.xml ./pom.xml
docker build -f quarkus/Dockerfile -t unicorn-store-quarkus:latest .
