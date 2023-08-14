#!/bin/bash

echo $(date '+%Y.%m.%d %H:%M:%S') $(~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timediff.sh $2 $(date +%s)) $1
