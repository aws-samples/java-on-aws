#bin/sh
date
start=`date +%s`
./10-deploy-ci.sh
./11-deploy-copilot.sh
./12-deploy-ecs.sh
./20-deploy-eks.sh
./21-deploy-gitops.sh
date
end=`date +%s`
runtime=$((end-start))
echo $runtime