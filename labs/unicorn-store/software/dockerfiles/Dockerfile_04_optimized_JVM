FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

RUN yum install -y tar gzip unzip

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package && mv target/store-spring-1.0.0-exec.jar target/store-spring.jar && cd target && unzip store-spring.jar

RUN jdeps --ignore-missing-deps \
    --multi-release 21 --print-module-deps \
    --class-path="target/BOOT-INF/lib/*" \
    target/store-spring.jar > jre-deps.info

# Adding jdk.crypto.ec for TLS 1.3 support
RUN truncate --size -1 jre-deps.info
RUN echo ",jdk.crypto.ec" >> jre-deps.info && cat jre-deps.info

RUN export JAVA_TOOL_OPTIONS=\"-Djdk.lang.Process.launchMechanism=vfork\" && \
    jlink --verbose --compress 2 --strip-java-debug-attributes \
    --no-header-files --no-man-pages --output custom-jre \
    --add-modules $(cat jre-deps.info)

FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN yum install -y shadow-utils

COPY --from=builder target/store-spring.jar store-spring.jar
COPY --from=builder custom-jre custom-jre

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000

EXPOSE 8080
ENTRYPOINT ["./custom-jre/bin/java","-jar","-Dserver.port=8080","/store-spring.jar"]
