FROM ghcr.io/graalvm/graalvm-community:17 AS build-aot

RUN microdnf install -y unzip zip

RUN \
    curl -s "https://get.sdkman.io" | bash; \
    bash -c "source $HOME/.sdkman/bin/sdkman-init.sh; \
    sdk install maven;"

COPY ./pom.xml ./pom.xml
COPY src ./src/

ENV MAVEN_OPTS='-Xmx8g'

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && mvn -Dmaven.test.skip=true clean package -Pnative"

FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20231218.0
RUN yum install -y shadow-utils

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

COPY --from=build-aot /app/target/store-spring /

USER 1000:1000

EXPOSE 8080

CMD ["./store-spring", "-Dserver.port=8080"]
