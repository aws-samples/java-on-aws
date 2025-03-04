#bin/sh

POD_NAME=$(kubectl get pods -n unicorn-store-spring | grep Running | awk '{print $1}')
echo POD_NAME is $POD_NAME

kubectl exec -it $POD_NAME -n unicorn-store-spring -- /bin/bash -c "/async-profiler/bin/asprof start -e wall jps && /async-profiler/bin/asprof status jps"
SVC_URL=$(~/java-on-aws/infrastructure/scripts/test/getsvcurl.sh eks) && echo $SVC_URL
~/java-on-aws/infrastructure/scripts/test/benchmark.sh $SVC_URL 60 200
kubectl exec -it $POD_NAME -n unicorn-store-spring -- /bin/bash -c "mkdir -p /home/spring/profiling && /async-profiler/bin/asprof stop -f /home/spring/profiling/profile-%t.html jps"
