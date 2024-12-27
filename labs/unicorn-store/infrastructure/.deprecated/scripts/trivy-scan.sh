#bin/sh

# install trivy amazon linux 2
# sudo vim /etc/yum.repos.d/trivy.repo
# [trivy]
# name=Trivy repository
# baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/5/$basearch/
# gpgcheck=0
# enabled=1
# sudo yum -y update
# sudo yum -y install trivy

# docker image prune --all --force
# docker system prune

cd ~/environment/unicorn-store-spring

# docker build -t unicorn-store-spring:latest . --no-cache

for i in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep 168223352661.dkr.ecr.eu-central-1.amazonaws.com/unicorn-store-spring | sort); do
    trivy image "$i"
done
