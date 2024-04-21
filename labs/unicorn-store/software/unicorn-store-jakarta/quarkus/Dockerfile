FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 as builder

RUN yum install -y tar gzip

COPY ./pom.xml ./pom.xml
RUN mvn dependency:go-offline -f ./pom.xml

COPY src ./src/
RUN mvn clean package
RUN rm -rf ~/.m2/repository

FROM public.ecr.aws/docker/library/amazoncorretto:21.0.2-al2023
RUN yum install -y shadow-utils

COPY --from=builder target/quarkus-app quarkus-app

RUN groupadd --system quarkus -g 1000
RUN adduser quarkus -u 1000 -g 1000

USER 1000:1000

EXPOSE 8080
ENTRYPOINT ["java","-jar","-Dserver.port=8080","/quarkus-app/quarkus-run.jar"]
