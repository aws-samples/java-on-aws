#!/bin/bash

BASE_DIR="/home/ec2-user/environment/unicorn-store-spring"

echo "Updating Dockerfile ..."
cat > "$BASE_DIR/Dockerfile" << 'EOF'
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-21-al2023 AS builder

RUN yum install -y wget tar gzip
RUN cd /tmp && \
    wget https://github.com/async-profiler/async-profiler/releases/download/v4.1/async-profiler-4.1-linux-x64.tar.gz && \
    mkdir /async-profiler && \
    tar -xvzf ./async-profiler-4.1-linux-x64.tar.gz -C /async-profiler --strip-components=1

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar

FROM amazoncorretto:21-alpine AS runtime

RUN addgroup -g 1000 -S spring && adduser -D -u 1000 -G spring spring

COPY --from=builder /async-profiler/ /async-profiler/
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

docker tag unicorn-store-spring:latest $ECR_URI:profiling
docker push $ECR_URI:profiling
docker tag unicorn-store-spring:latest $ECR_URI:latest
docker push $ECR_URI:latest

echo "Creating persistence ..."
mkdir -p "$BASE_DIR/k8s"

S3_BUCKET=$(aws ssm get-parameter --name unicornstore-lambda-bucket-name --query 'Parameter.Value' --output text)

cat <<EOF > "$BASE_DIR/k8s/persistence.yaml"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-profiling-pv
spec:
  capacity:
    storage: 1200Gi # ignored, required
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  mountOptions:
    - allow-other
    - uid=1000
    - gid=1000
    - allow-delete
  csi:
    driver: s3.csi.aws.com # required
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: ${S3_BUCKET}
      authenticationSource: pod
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-profiling-pvc
  namespace: unicorn-store-spring
spec:
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  storageClassName: "" # required for static provisioning
  resources:
    requests:
      storage: 1200Gi # ignored, required
  volumeName: s3-profiling-pv
EOF

kubectl apply -f "$BASE_DIR/k8s/persistence.yaml"

echo "Updating deployment ..."
yq eval '.spec.template.metadata.annotations."prometheus.io/scrape" = "true"' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.metadata.annotations."prometheus.io/port" = "8080"' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.metadata.annotations."prometheus.io/path" = "/actuator/prometheus"' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.spec.containers[0].command = ["/bin/sh", "-c"]' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.spec.containers[0].args = ["mkdir -p /s3/profiling/$HOSTNAME && cd /s3/profiling/$HOSTNAME; java -agentpath:/async-profiler/lib/libasyncProfiler.so=start,event=wall,file=./%t.txt,loop=30s,collapsed -jar -Dserver.port=8080 /store-spring.jar;"]' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.spec.containers[0].volumeMounts = [{"name": "persistent-storage", "mountPath": "/s3"}]' -i "$BASE_DIR/k8s/deployment.yaml"
yq eval '.spec.template.spec.volumes = [{"name": "persistent-storage", "persistentVolumeClaim": {"claimName": "s3-profiling-pvc"}}]' -i "$BASE_DIR/k8s/deployment.yaml"

kubectl apply -f "$BASE_DIR/k8s/deployment.yaml"
