#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

echo Create a new directory k8s in the application folder:
mkdir ~/environment/unicorn-store-spring/k8s
cd ~/environment/unicorn-store-spring/k8s

echo Create a manifest file for a deployment and service:
export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring \
  | jq --raw-output '.repositories[0].repositoryUri')
export SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString \
  | jq --raw-output '.Parameter.Value')

cat <<EOF > ~/environment/unicorn-store-spring/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
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
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
EOF

cat <<EOF > ~/environment/unicorn-store-spring/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
    app: unicorn-store-spring
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: unicorn-store-spring
EOF

echo Deploy the template to EKS cluster:
kubectl apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl apply -f ~/environment/unicorn-store-spring/k8s/service.yaml

echo Verify that the application is running properly:
kubectl wait deployment -n unicorn-store-spring unicorn-store-spring --for condition=Available=True --timeout=120s
kubectl get deploy -n unicorn-store-spring
export SVC_URL=http://$(kubectl get svc unicorn-store-spring -n unicorn-store-spring -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
echo Service is Ready!

echo Get the Load Balancer URL and make an example API call:
export SVC_URL=http://$(kubectl get svc unicorn-store-spring -n unicorn-store-spring -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

echo $SVC_URL
curl --location $SVC_URL; echo
