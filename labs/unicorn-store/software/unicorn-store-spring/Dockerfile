FROM maven:3-amazoncorretto-17 as builder

RUN yum install -y shadow-utils

COPY ./pom.xml ./pom.xml
RUN mvn dependency:go-offline -f ./pom.xml

COPY src ./src/
RUN mvn clean package && mv target/store-spring-1.0.0.jar store-spring.jar

RUN groupadd --system spring
RUN adduser spring -g spring

USER spring:spring

EXPOSE 8080
ENTRYPOINT ["java","-jar","-Dserver.port=8080","/store-spring.jar"]
