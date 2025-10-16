#!/bin/bash

BASE_DIR="/home/ec2-user/environment/unicorn-store-spring"

echo "Removing unnecessary files ..."
rm -rf "$BASE_DIR/src/assembly" 2>/dev/null
rm -rf "$BASE_DIR/src/main/java/com/unicorn/store/config" 2>/dev/null
rm -rf "$BASE_DIR/src/main/java/com/unicorn/store/otel" 2>/dev/null
rm -rf "$BASE_DIR/src/main/java/com/unicorn/store/monitoring" 2>/dev/null
rm -f "$BASE_DIR/src/main/java/com/unicorn/store/controller/ThreadManagementController.java" 2>/dev/null
rm -f "$BASE_DIR/src/main/java/com/unicorn/store/service/ThreadGeneratorService.java" 2>/dev/null

echo "Removing dockerfiles ..."
rm -rf "/home/ec2-user/environment/unicorn-store-spring/dockerfiles" 2>/dev/null

echo "Updating application.properties ..."
cat > "$BASE_DIR/src/main/resources/application.properties" << 'EOF'
spring.datasource.username=postgres
spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.open-in-view=false
spring.jpa.properties.hibernate.temp.use_jdbc_metadata_defaults=false
spring.jpa.hibernate.ddl-auto=none

spring.datasource.hikari.initialization-fail-timeout=0
spring.datasource.hikari.maximumPoolSize=1
spring.datasource.hikari.allow-pool-suspension=true
spring.datasource.hikari.data-source-properties.preparedStatementCacheQueries=0

# Virtual Threads
spring.threads.virtual.enabled=true
EOF

echo "Updating Dockerfile ..."
cat > "$BASE_DIR/Dockerfile" << 'EOF'
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar

FROM amazoncorretto:21-alpine AS runtime

RUN addgroup -g 1000 -S spring && adduser -D -u 1000 -G spring spring

COPY --from=builder store-spring.jar store-spring.jar

USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java","-jar","-Dserver.port=8080","/store-spring.jar"]
EOF

echo "Building a container image ..."
cd "$BASE_DIR"
ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URI

docker build -t unicorn-store-spring:latest .

docker tag unicorn-store-spring:latest $ECR_URI:latest
docker push $ECR_URI:latest
docker tag unicorn-store-spring:latest $ECR_URI:baseline
docker push $ECR_URI:baseline

echo "Deploying to EKS ..."
mkdir -p "$BASE_DIR/k8s"

ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name unicornstore-db-connection-string | jq --raw-output '.Parameter.Value')

cat <<EOF > "$BASE_DIR/k8s/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
    project: unicorn-store
    app: unicorn-store-spring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unicorn-store-spring
  template:
    metadata:
      labels:
        app: unicorn-store-spring
    spec:
      nodeSelector:
        karpenter.sh/nodepool: dedicated
      serviceAccountName: unicorn-store-spring
      containers:
        - name: unicorn-store-spring
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "1"
              memory: "2Gi"
          image: ${ECR_URI}:latest
          imagePullPolicy: Always
          env:
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "unicornstore-db-secret"
                  key: "password"
                  optional: false
            - name: SPRING_DATASOURCE_URL
              value: ${SPRING_DATASOURCE_URL}
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 6
            periodSeconds: 10
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            failureThreshold: 6
            periodSeconds: 10
            timeoutSeconds: 5
            initialDelaySeconds: 30
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 15
            periodSeconds: 10
            timeoutSeconds: 5
            initialDelaySeconds: 30
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
EOF
kubectl apply -f "$BASE_DIR/k8s/deployment.yaml"

cat <<EOF > "$BASE_DIR/k8s/service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
    project: unicorn-store
    app: unicorn-store-spring
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: unicorn-store-spring
EOF
kubectl apply -f "$BASE_DIR/k8s/service.yaml"

cat <<EOF > "$BASE_DIR/k8s/ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  labels:
    project: unicorn-store
    app: unicorn-store-spring
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: unicorn-store-spring
                port:
                  number: 80
EOF
kubectl apply -f "$BASE_DIR/k8s/ingress.yaml"

kubectl wait deployment unicorn-store-spring -n unicorn-store-spring --for condition=Available=True --timeout=120s
kubectl get deployment unicorn-store-spring -n unicorn-store-spring
SVC_URL=http://$(kubectl get ingress unicorn-store-spring -n unicorn-store-spring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL

echo
echo Service is Ready!
echo
echo $SVC_URL
echo
curl --location $SVC_URL; echo
echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

kubectl logs $(kubectl get pods -n unicorn-store-spring -o json | jq --raw-output '.items[0].metadata.name') -n unicorn-store-spring
kubectl logs $(kubectl get pods -n unicorn-store-spring -o json | jq --raw-output '.items[0].metadata.name') -n unicorn-store-spring | grep "Started StoreApplication"

echo "App deployment to EKS cluster is complete."

echo "Commiting changes ..."
git add .
git commit -m "Initial deployment"

echo "{ \"query\": { \"folder\": \"/home/ec2-user/environment\" } }" > /home/ec2-user/.local/share/code-server/coder.json
