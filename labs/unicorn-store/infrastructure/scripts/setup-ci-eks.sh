#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
cd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts

# setup CI
start_time=`date +%s`
pushd ~/environment/unicorn-store-spring
cp dockerfiles/Dockerfile_03_otel Dockerfile
popd
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/10-deploy-ci.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "ci" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# setup EKS
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-eks-eksctl.sh
# add arm64 nodegroup
eksctl create nodegroup --cluster unicorn-store-spring --name managed-node-group-arm64 --managed \
--node-type m6g.large --nodes 2 --nodes-min 2 --nodes-max 4
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# setup GitOps
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-gitops.sh

# enable otel
pushd ~/environment/unicorn-store-spring-gitops
git pull
export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
export SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString | jq --raw-output '.Parameter.Value')
envsubst < ./deployment-with-otel.yaml > ./deployment-with-otel-new.yaml
mv ./deployment-with-otel-new.yaml ./apps/deployment.yaml
git add . && git commit -m "enable otel" && git push
popd
flux reconcile source git flux-system -n flux-system
sleep 10
flux reconcile kustomization apps -n flux-system
sleep 10
git -C ~/environment/unicorn-store-spring-gitops pull
kubectl wait deployment -n unicorn-store-spring unicorn-store-spring --for condition=Available=True --timeout=120s

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "gitops" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished" $init_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)