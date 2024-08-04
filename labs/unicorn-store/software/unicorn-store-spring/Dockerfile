FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

RUN yum install -y shadow-utils

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package && mv target/store-spring-1.0.0-exec.jar store-spring.jar
RUN rm -rf ~/.m2/repository

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000

EXPOSE 8080
ENTRYPOINT ["java","-jar","-Dserver.port=8080","/store-spring.jar"]
