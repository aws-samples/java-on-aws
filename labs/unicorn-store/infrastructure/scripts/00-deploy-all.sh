#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started" $start_time

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/10-deploy-ci.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/11-deploy-copilot.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/12-deploy-ecs.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/20-deploy-eks.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/deploy-gitops.sh

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished" $start_time
