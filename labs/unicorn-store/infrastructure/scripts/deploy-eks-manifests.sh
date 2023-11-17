#bin/sh

export APP_NAME=unicorn-store-spring

echo $(date '+%Y.%m.%d %H:%M:%S')

echo Create a new directory k8s in the application folder:
mkdir ~/environment/$APP_NAME/k8s
cd ~/environment/$APP_NAME/k8s

echo Create a manifest file for a deployment and service:
export ECR_URI=$(aws ecr describe-repositories --repository-names $APP_NAME \
  | jq --raw-output '.repositories[0].repositoryUri')
export SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString \
  | jq --raw-output '.Parameter.Value')

cat <<EOF > ~/environment/$APP_NAME/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      serviceAccountName: $APP_NAME
      containers:
        - name: $APP_NAME
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
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 6
            periodSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
EOF

cat <<EOF > ~/environment/$APP_NAME/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: $APP_NAME
EOF

echo Deploy the template to EKS cluster:
kubectl apply -f ~/environment/$APP_NAME/k8s/deployment.yaml
kubectl apply -f ~/environment/$APP_NAME/k8s/service.yaml

echo Verify that the application is running properly:
kubectl wait deployment -n $APP_NAME $APP_NAME --for condition=Available=True --timeout=120s
kubectl get deploy -n $APP_NAME
export SVC_URL=http://$(kubectl get svc $APP_NAME -n $APP_NAME -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
echo Service is Ready!

echo Get the Load Balancer URL and make an example API call:
export SVC_URL=http://$(kubectl get svc $APP_NAME -n $APP_NAME -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
echo $SVC_URL
curl --location $SVC_URL; echo
