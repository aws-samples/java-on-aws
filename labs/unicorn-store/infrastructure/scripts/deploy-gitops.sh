#bin/sh

export CLUSTER_NAME=unicorn-store
export APP_NAME=unicorn-store-spring
export GITOPS_USER=unicorn-store-gitops
export GITOPSC_REPO_NAME=unicorn-store-gitops

echo $(date '+%Y.%m.%d %H:%M:%S')

pushd ~/environment

echo Create a repository which will contain Kubernetes manifests.
# export CC_POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSCodeCommitPowerUser`].{ARN:Arn}' --output text)

# aws iam create-user --user-name $GITOPS_USER
# aws iam attach-user-policy --user-name $GITOPS_USER --policy-arn $CC_POLICY_ARN

aws codecommit create-repository --repository-name $GITOPSC_REPO_NAME --repository-description "GitOps repository"
export GITOPS_REPO_URL=$(aws codecommit get-repository --repository-name $GITOPSC_REPO_NAME --query 'repositoryMetadata.cloneUrlHttp' --output text)

echo Create credentials for accessing the Git repository
aws iam create-service-specific-credential --user-name $GITOPS_USER --service-name codecommit.amazonaws.com
export SSC_ID=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceSpecificCredentialId' --output text)
export SSC_USER=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceUserName' --output text)
export SSC_PWD=$(aws iam reset-service-specific-credential --user-name $GITOPS_USER --service-specific-credential-id $SSC_ID --query 'ServiceSpecificCredential.ServicePassword' --output text)
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

sleep 20

echo Install Flux agent into EKS cluster
flux bootstrap git \
  --components-extra=image-reflector-controller,image-automation-controller \
  --url=$GITOPS_REPO_URL \
  --token-auth=true \
  --branch=main \
  --username=$SSC_USER \
  --password=$SSC_PWD

echo Clone the Git repository and copy initial Flux GitOps configuration
echo "${GITOPS_REPO_URL}"
git clone ${GITOPS_REPO_URL}
# rsync -av ~/environment/java-on-aws/labs/unicorn-store/infrastructure/gitops/ "${GITOPS_REPO_URL##*/}"
cp -R ~/environment/java-on-aws/labs/unicorn-store/infrastructure/gitops/apps "${GITOPS_REPO_URL##*/}"
cp -R ~/environment/java-on-aws/labs/unicorn-store/infrastructure/gitops/apps.yaml "${GITOPS_REPO_URL##*/}"
cd "${GITOPS_REPO_URL##*/}"
git config pull.rebase true

echo Prepare new deployment files
export SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString | jq --raw-output '.Parameter.Value')
export ECR_URI=$(aws ecr describe-repositories --repository-names $APP_NAME | jq --raw-output '.repositories[0].repositoryUri')
export imagepolicy=\$imagepolicy

envsubst < ./apps/deployment.yaml > ./apps/deployment_new.yaml
mv ./apps/deployment_new.yaml ./apps/deployment.yaml

echo Delete the manual deployment
kubectl delete deployment $APP_NAME -n $APP_NAME

echo Commit changes to the Git repository. Flux will trigger a new deployment
git -C ~/environment/$GITOPSC_REPO_NAME pull
git -C ~/environment/$GITOPSC_REPO_NAME add .
git -C ~/environment/$GITOPSC_REPO_NAME commit -m "initial commit"
git -C ~/environment/$GITOPSC_REPO_NAME push

# git add . && git commit -m "initial commit" && git push

echo Flux Image Updater
cat <<EOF | envsubst | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: $APP_NAME
  namespace: flux-system
spec:
  provider: aws
  interval: 1m
  image: ${ECR_URI}
  accessFrom:
    namespaceSelectors:
      - matchLabels:
          kubernetes.io/metadata.name: flux-system
EOF

cat <<EOF | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: $APP_NAME
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: $APP_NAME
  filterTags:
    pattern: '^i[a-fA-F0-9]'
  policy:
    alphabetical:
      order: asc
EOF

cat <<EOF | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: $APP_NAME
  namespace: flux-system
spec:
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
      messageTemplate: '{{range .Updated.Images}}{{println .}}{{end}}'
    push:
      branch: main
  interval: 1m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  update:
    path: ./apps
    strategy: Setters
EOF

echo Check the status of the deployment
# flux get kustomization --watch
# kubectl -n $APP_NAME get all
# kubectl get events -n $APP_NAME
flux reconcile source git flux-system -n flux-system
sleep 10
flux reconcile kustomization apps -n flux-system
sleep 10
git -C ~/environment/$GITOPSC_REPO_NAME pull

echo Verify that the application is running properly
kubectl wait deployment -n $APP_NAME $APP_NAME --for condition=Available=True --timeout=120s
kubectl get deploy -n $APP_NAME
export SVC_URL=http://$(kubectl get svc $APP_NAME -n $APP_NAME -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
echo Service is Ready!

echo Get the Load Balancer URL and make an example API call
echo $SVC_URL
curl --location $SVC_URL; echo

popd
