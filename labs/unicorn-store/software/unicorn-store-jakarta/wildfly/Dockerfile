FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

RUN yum install -y tar gzip

COPY ./pom.xml ./pom.xml
RUN mvn dependency:go-offline -f ./pom.xml

COPY src ./src/
RUN mvn clean package
RUN rm -rf ~/.m2/repository

FROM quay.io/wildfly/wildfly:32.0.1.Final-jdk17

# RUN /opt/jboss/wildfly/bin/add-user.sh admin wildfly! --silent

ENV POSTGRESQL_JDBC_DRIVER_VERSION=42.7.2
RUN wget "https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRESQL_JDBC_DRIVER_VERSION}/postgresql-${POSTGRESQL_JDBC_DRIVER_VERSION}.jar" -O $JBOSS_HOME/postgresql.jar
RUN printenv > $JBOSS_HOME/env.properties

COPY ./wildfly/datasource.cli $JBOSS_HOME/datasource.cli

RUN /opt/jboss/wildfly/bin/jboss-cli.sh --echo-command --file="$JBOSS_HOME/datasource.cli" --properties="$JBOSS_HOME/env.properties"
RUN rm /opt/jboss/wildfly/standalone/configuration/standalone_xml_history/current/*

COPY --from=builder target/store-wildfly.war $JBOSS_HOME/standalone/deployments/store-wildfly.war

USER 1000:1000

CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0", "-bmanagement", "0.0.0.0"]
