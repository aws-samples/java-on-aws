set -e

APP_NAME=${1:-"unicorn-store-spring"}
PROJECT_NAME=${2:-"unicorn-store"}

echo Creating manifests for $APP_NAME ...

mkdir -p ~/environment/${APP_NAME}/k8s
cd ~/environment/${APP_NAME}/k8s

# cat <<EOF > ~/environment/${APP_NAME}/k8s/namespace.yaml
# apiVersion: v1
# kind: Namespace
# metadata:
#   name: $APP_NAME
#   labels:
#     project: $PROJECT_NAME
#     app: $APP_NAME
# EOF
# kubectl apply -f ~/environment/${APP_NAME}/k8s/namespace.yaml

# cat <<EOF > ~/environment/${APP_NAME}/k8s/serviceaccount.yaml
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: $APP_NAME
#   namespace: $APP_NAME
#   labels:
#     project: $PROJECT_NAME
#     app: $APP_NAME
# EOF

# kubectl apply -f ~/environment/${APP_NAME}/k8s/serviceaccount.yaml

# while ! kubectl get secret unicornstore-db-secret -n ${APP_NAME} >/dev/null 2>&1; do echo "Secret not found, waiting..." && sleep 5; done

ECR_URI=$(aws ecr describe-repositories --repository-names $APP_NAME \
  | jq --raw-output '.repositories[0].repositoryUri')
SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString \
  | jq --raw-output '.Parameter.Value')

cat <<EOF > ~/environment/$APP_NAME/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
  labels:
    project: $PROJECT_NAME
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
      nodeSelector:
        karpenter.sh/nodepool: dedicated
      serviceAccountName: $APP_NAME
      containers:
        - name: $APP_NAME
          resources:
            requests:
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
            periodSeconds: 5
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            failureThreshold: 6
            periodSeconds: 5
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 6
            initialDelaySeconds: 10
            periodSeconds: 5
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
    project: $PROJECT_NAME
    app: $APP_NAME
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: $APP_NAME
EOF

cat <<EOF > ~/environment/$APP_NAME/k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  labels:
    project: $PROJECT_NAME
    app: $APP_NAME
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $APP_NAME
                port:
                  number: 80
EOF

echo Deploying the manifests to the EKS cluster ...
kubectl apply -f ~/environment/$APP_NAME/k8s/

echo Verifying that the application is running properly
kubectl wait deployment $APP_NAME -n $APP_NAME --for condition=Available=True --timeout=120s
kubectl get deployment $APP_NAME -n $APP_NAME
SVC_URL=http://$(kubectl get ingress $APP_NAME -n $APP_NAME -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

echo "App deployment to EKS cluster is complete."
