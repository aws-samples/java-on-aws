# Java-on-EKS startup optimization (measured) + golden Dockerfiles

Measured startup for `unicorn-store-spring` (Corretto JDK 25) at 1 vCPU / 2Gi baseline, and the exact, working Dockerfiles. Use these Dockerfiles VERBATIM — do not invent flags, tags, or a `sleep + jcmd JDK.checkpoint` checkpoint step.

## Measured results

| Technique | Startup | RSS | Notes |
|---|---|---|---|
| Baseline (1 vCPU) | ~13 s | ~370 Mi | plain JVM, SerialGC |
| In-place CPU boost (2→1 vCPU) | ~6 s | — | no code/image change; 0 restarts |
| AOT cache (JDK 25) | ~4.8 s | ~348 Mi | zero code change |
| CRaC (Azul Zulu 25 + Warp) | **~0.194 s** | **~190 Mi** | fastest + leanest; userspace, no privilege |

CRaC is fastest AND lowest RSS. Warp is a **userspace** engine: **no CRIU, no `privileged`, no `CHECKPOINT_RESTORE`/`SYS_PTRACE` capability** needed. The checkpoint is taken at image-build time via `-Dspring.context.checkpoint=onRefresh` (fires after the Spring context refreshes, before the HTTP port opens) — NOT via a `sleep` + `jcmd JDK.checkpoint` hack.

## Golden AOT Dockerfile (JDK 25 AOT cache, zero code change) → ~4.8 s

```dockerfile
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp \
    -Dspring-boot.aot.enabled=true && \
    mv target/store-spring-1.0.0-exec.jar app.jar

FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023 AS trainer

COPY --from=builder app.jar app.jar

RUN mkdir -p /ex && (cd /ex && jar -xf /app.jar) && \
    mkdir -p /opt/app/training /opt/app/lib && \
    (cd /ex/BOOT-INF/classes && jar -cf /opt/app/training/classes.jar .) && \
    cp -r /ex/BOOT-INF/lib/* /opt/app/lib/

RUN ls /opt/app/lib/*.jar | sort | tr '\n' ':' | sed 's/:$//' > /opt/app/lib-cp.txt

ENV MAIN_CLASS="com.unicorn.store.StoreApplication"

ARG SPRING_DATASOURCE_URL
ARG SPRING_DATASOURCE_USERNAME
ARG SPRING_DATASOURCE_PASSWORD

ENV TRAINING_JAVA_OPTS_DEFAULT="-Dspring.autoconfigure.exclude=org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration,org.springframework.boot.autoconfigure.liquibase.LiquibaseAutoConfiguration -Dspring.main.lazy-initialization=true"

RUN set -e; \
    if [ -n "${SPRING_DATASOURCE_URL}" ]; then \
        OPTS="-Dspring.datasource.url=${SPRING_DATASOURCE_URL} -Dspring.datasource.username=${SPRING_DATASOURCE_USERNAME} -Dspring.datasource.password=${SPRING_DATASOURCE_PASSWORD}"; \
    else \
        OPTS="${TRAINING_JAVA_OPTS_DEFAULT}"; \
    fi; \
    java -XX:AOTMode=record -XX:AOTConfiguration=/app.aotconf \
    -cp "/opt/app/training/classes.jar:$(cat /opt/app/lib-cp.txt)" \
    -Dspring.context.exit=onRefresh ${OPTS} ${MAIN_CLASS} || true && \
    test -s /app.aotconf

RUN set -e; \
    if [ -n "${SPRING_DATASOURCE_URL}" ]; then \
        OPTS="-Dspring.datasource.url=${SPRING_DATASOURCE_URL} -Dspring.datasource.username=${SPRING_DATASOURCE_USERNAME} -Dspring.datasource.password=${SPRING_DATASOURCE_PASSWORD}"; \
    else \
        OPTS="${TRAINING_JAVA_OPTS_DEFAULT}"; \
    fi; \
    java -XX:AOTMode=create -XX:AOTConfiguration=/app.aotconf \
    -XX:AOTCache=/opt/app/app.aot \
    -cp "/opt/app/training/classes.jar:$(cat /opt/app/lib-cp.txt)" \
    ${OPTS} ${MAIN_CLASS} || true && \
    test -s /opt/app/app.aot

FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023

RUN yum install -y shadow-utils && \
    groupadd --system spring -g 1000 && \
    adduser spring -u 1000 -g 1000

COPY --from=trainer --chown=1000:1000 /opt/app/training/classes.jar /opt/app/training/classes.jar
COPY --from=trainer --chown=1000:1000 /opt/app/lib/ /opt/app/lib/
COPY --from=trainer --chown=1000:1000 /opt/app/app.aot /opt/app/app.aot
COPY --from=trainer --chown=1000:1000 /opt/app/lib-cp.txt /opt/app/lib-cp.txt

USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["sh", "-c", "exec java -XX:AOTCache=/opt/app/app.aot -Dserver.port=8080 -cp /opt/app/training/classes.jar:$(cat /opt/app/lib-cp.txt) com.unicorn.store.StoreApplication"]
```

## Golden CRaC Dockerfile (Azul Zulu 25 + Warp) → ~0.194 s, ~190 Mi

```dockerfile
FROM azul/zulu-openjdk:25-jdk-crac-latest AS builder

RUN apt-get -qq update && apt-get -qq install -y curl maven

ARG SPRING_DATASOURCE_URL
ENV SPRING_DATASOURCE_URL=$SPRING_DATASOURCE_URL
ARG SPRING_DATASOURCE_USERNAME
ENV SPRING_DATASOURCE_USERNAME=$SPRING_DATASOURCE_USERNAME
ARG SPRING_DATASOURCE_PASSWORD
ENV SPRING_DATASOURCE_PASSWORD=$SPRING_DATASOURCE_PASSWORD

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar

# Take checkpoint using Warp engine (no CRIU, no extra privileges).
# spring.context.checkpoint=onRefresh fires after the Spring context refreshes,
# before the HTTP port opens. Do NOT use a sleep + jcmd JDK.checkpoint hack.
RUN java -Dspring.context.checkpoint=onRefresh \
    -Djdk.crac.collect-fd-stacktraces=true \
    -XX:CRaCEngine=warp \
    -XX:CPUFeatures=generic \
    -XX:CRaCCheckpointTo=/opt/crac-files \
    -jar /store-spring.jar & PID=$! && wait ${PID} || true

FROM azul/zulu-openjdk:25-jdk-crac-latest

RUN apt-get -qq update && apt-get -qq install -y adduser \
    && addgroup --system --gid 1000 spring \
    && adduser --system --disabled-password --gecos "" --uid 1000 --gid 1000 spring

COPY --from=builder --chown=1000:1000 /opt/crac-files /opt/crac-files
COPY --from=builder --chown=1000:1000 /store-spring.jar /store-spring.jar

USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["java", "-XX:CRaCEngine=warp", "-XX:CRaCRestoreFrom=/opt/crac-files", "-Dserver.port=8080"]
```

No Kubernetes `securityContext` changes are needed for CRaC/Warp — do NOT add `privileged`, `CHECKPOINT_RESTORE`, or `SYS_PTRACE`.
