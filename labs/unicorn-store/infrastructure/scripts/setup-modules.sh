#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
cd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts

# # setup EKS
# start_time=`date +%s`
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-eks-eksctl.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# # setup GitOps
# start_time=`date +%s`
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-gitops.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "gitops" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished" $init_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)
