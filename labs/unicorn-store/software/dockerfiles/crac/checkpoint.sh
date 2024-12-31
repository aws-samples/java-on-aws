#! /bin/bash

# create directory if it doesn't exist
mkdir -p /opt/crac-files/

# delete old snapshot files
rm -rf /opt/crac-files/*
echo Starting the application...
( echo 128 > /proc/sys/kernel/ns_last_pid ) 2>/dev/null || while [ $(cat /proc/sys/kernel/ns_last_pid) -lt 128 ]; do :; done;
java -Dspring.context.checkpoint=onRefresh -Dspring.profiles.active=prod -Djdk.crac.collect-fd-stacktraces=true -XX:CPUFeatures=0x214e1805ddfbff,0x3e6 -XX:CRaCCheckpointTo=/opt/crac-files/ -jar /store-spring.jar

EXIT_CODE=$?

# Error code 137 is expected, because process is killed
if [ $EXIT_CODE -eq 137 ]
then
# let's check if there are snapshot files
   if [ -z "$(ls -A /opt/crac-files/)" ]
   then
      echo "Directory is empty, exiting with -1"
      exit -1
    fi
fi

exit 0