FROM quay.io/wildfly/wildfly:29.0.1.Final-jdk17

RUN /opt/jboss/wildfly/bin/add-user.sh admin wildfly! --silent

COPY ./src/main/wildfly/postgresql.cli $JBOSS_HOME/postgresql.cli

ENV POSTGRESQL_JDBC_DRIVER_VERSION 42.6.0
RUN wget "https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRESQL_JDBC_DRIVER_VERSION}/postgresql-${POSTGRESQL_JDBC_DRIVER_VERSION}.jar" -O $JBOSS_HOME/postgresql.jar
RUN printenv > $JBOSS_HOME/env.properties
RUN /opt/jboss/wildfly/bin/jboss-cli.sh --echo-command --file="$JBOSS_HOME/postgresql.cli" --properties="$JBOSS_HOME/env.properties"
RUN rm /opt/jboss/wildfly/standalone/configuration/standalone_xml_history/current/*

CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0", "-bmanagement", "0.0.0.0"]
