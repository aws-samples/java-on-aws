#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
cd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts

# # setup EKS
# start_time=`date +%s`

# # Build an image
# export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
# aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

# cd ~/environment/unicorn-store-spring
# docker buildx build --load -t unicorn-store-spring:latest .
# IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
# docker tag unicorn-store-spring:latest $ECR_URI:$IMAGE_TAG
# docker tag unicorn-store-spring:latest $ECR_URI:latest
# docker push $ECR_URI:$IMAGE_TAG
# docker push $ECR_URI:latest

# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-eks-eksctl.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# # setup GitOps
# start_time=`date +%s`
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-gitops.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "gitops" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished" $init_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)
