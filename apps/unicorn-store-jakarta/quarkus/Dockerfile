FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

COPY ./pom.xml ./pom.xml
COPY src ./src/
RUN mvn clean package --no-transfer-progress

FROM public.ecr.aws/docker/library/amazoncorretto:21-al2023
RUN yum install -y shadow-utils

COPY --from=builder target/quarkus-app quarkus-app

RUN groupadd --system quarkus -g 1000
RUN adduser quarkus -u 1000 -g 1000
USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["java","-jar","-Dserver.port=8080","/quarkus-app/quarkus-run.jar"]