#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-eks-manifests ..." $start_time

export CLUSTER_NAME=unicorn-store
export APP_NAME=unicorn-store-spring

if [[ -z "${ACCOUNT_ID}" ]]; then
  export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
  echo ACCOUNT_ID is set to $ACCOUNT_ID
else
  echo ACCOUNT_ID was set to $ACCOUNT_ID
fi
if [[ -z "${AWS_REGION}" ]]; then
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
  echo AWS_REGION is set to $AWS_REGION
else
  echo AWS_REGION was set to $AWS_REGION
fi

STACK_NAME="eksctl-$CLUSTER_NAME-podidentityrole-kube-system-karpenter"

check_stack() {
    STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null)

    case $STATUS in
        CREATE_COMPLETE|UPDATE_COMPLETE)
            echo "Stack $STACK_NAME is ready."
            return 0
            ;;
        CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS)
            echo "Stack $STACK_NAME is still in progress. Current status: $STATUS"
            return 1
            ;;
        *)
            if [ -z "$STATUS" ]; then
                echo "Stack $STACK_NAME does not exist or an error occurred while checking."
            else
                echo "Stack $STACK_NAME is in an unexpected state: $STATUS"
            fi
            return 1
            ;;
    esac
}

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
    secret_store_exists=$(kubectl get ClusterSecretStore unicorn-store 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ClusterSecretStore does not exist ..."
        return 1
    fi
    echo "ClusterSecretStore exists."
    return 0
}

while ! check_cluster; do sleep 10; done

while ! check_stack; do sleep 10; done

while ! aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME; do
    echo "Failed to update kubeconfig. Retrying in 10 seconds..."
    sleep 10
done

while ! kubectl get ns; do
    echo "Failed to get namespaces. Retrying in 10 seconds..."
    sleep 10
done

while ! check_secret_store; do sleep 10; done
kubectl get ClusterSecretStore unicorn-store

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
kubectl get ClusterSecretStore unicorn-store
kubectl apply -f ~/environment/$APP_NAME/k8s/secret.yaml
kubectl get ExternalSecret unicorn-store-db-secret -n $APP_NAME

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

echo Clean up
docker images --format "{{.Repository}}:{{.Tag}}" | grep unicorn-store-spring | xargs -r docker rmi
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-eks-manifests." $start_time
