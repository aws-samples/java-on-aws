#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started 99-destroy-all ..." $start_time

# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-cicd.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-apprunner.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-ecs.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-eks.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-ec2.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-destroy-lambda.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/destroy-infrastructure.sh

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished 99-destroy-all." $start_time
