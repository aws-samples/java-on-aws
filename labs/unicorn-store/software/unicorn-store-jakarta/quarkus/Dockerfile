FROM public.ecr.aws/amazoncorretto/amazoncorretto:17 as builder

RUN yum install -y tar gzip

## Install Additional dependencies
COPY ./scripts/installdeps.sh ./installdeps.sh
RUN ./installdeps.sh

COPY ./quarkus/pom.xml ./pom.xml
RUN mvn dependency:go-offline -f ./pom.xml

COPY src ./src/
RUN mvn clean package
RUN rm -rf ~/.m2/repository

FROM public.ecr.aws/amazoncorretto/amazoncorretto:17

RUN yum install -y shadow-utils

COPY --from=builder target/quarkus-app quarkus-app

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000

EXPOSE 8080
ENTRYPOINT ["java","-jar","-Dserver.port=8080","/quarkus-app/quarkus-run.jar"]