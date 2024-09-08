#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-eks-manifests ..." $start_time

export CLUSTER_NAME=unicorn-store
export APP_NAME=unicorn-store-spring

check_cluster() {
    cluster_status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.status" --output text 2>/dev/null)
    if [ "$cluster_status" != "ACTIVE" ]; then
        echo "EKS cluster is not active. Current status: $cluster_status ..."
        return 1
    fi
    echo "EKS cluster is active."
    return 0
}

check_secret_store() {
    secret_store_exists=$(kubectl get ClusterSecretStore 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ClusterSecretStore does not exist ..."
        return 1
    fi
    echo "ClusterSecretStore exists."
    return 0
}

while ! check_cluster; do sleep 10; done

while ! aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME; do
    echo "Failed to update kubeconfig. Retrying in 10 seconds..."
    sleep 10
done

kubectl get ns

while ! check_secret_store; do sleep 10; done
kubectl get ClusterSecretStore

echo Create a Kubernetes namespace for the application
kubectl create namespace $APP_NAME

echo Create a Kubernetes Service Account and associate the previously created IAM role with access to EventBridge and Parameter Store
kubectl create sa $APP_NAME -n $APP_NAME

aws eks create-pod-identity-association --cluster-name $CLUSTER_NAME \
  --namespace $APP_NAME --service-account $APP_NAME \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-pod-role

echo Create a new directory k8s in the application folder
mkdir ~/environment/$APP_NAME/k8s

echo Create the Kubernetes External Secret resources in the application namespace to access the database password
cat <<EOF > ~/environment/$APP_NAME/k8s/secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: unicorn-store-db-secret
  namespace: $APP_NAME
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: unicorn-store
    kind: ClusterSecretStore
  target:
    name: unicornstore-db-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: unicornstore-db-secret
        property: password
EOF

sleep 10
kubectl get ClusterSecretStore
kubectl apply -f ~/environment/$APP_NAME/k8s/secret.yaml
kubectl get ExternalSecret -n $APP_NAME

echo Create Kubernetes manifest files for the deployment and the service
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

git -C ~/environment/unicorn-store-spring add .
git -C ~/environment/unicorn-store-spring commit -m "add k8s manifests"

echo Deploy the template to EKS cluster
kubectl apply -f ~/environment/$APP_NAME/k8s/deployment.yaml
kubectl apply -f ~/environment/$APP_NAME/k8s/service.yaml

echo Verify that the application is running properly
kubectl wait deployment -n $APP_NAME $APP_NAME --for condition=Available=True --timeout=120s
kubectl get deploy -n $APP_NAME
SVC_URL=http://$(kubectl get svc $APP_NAME -n $APP_NAME -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-eks-manifests." $start_time
