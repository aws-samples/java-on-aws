#bin/sh

## Install Maven
cd /tmp
export MVN_VERSION=3.9.4
export MVN_FOLDERNAME=apache-maven-${MVN_VERSION}
export MVN_FILENAME=apache-maven-${MVN_VERSION}-bin.tar.gz
curl -4 -L https://archive.apache.org/dist/maven/maven-3/${MVN_VERSION}/binaries/${MVN_FILENAME} | tar -xvz
mv $MVN_FOLDERNAME /usr/lib/maven
export M2_HOME=/usr/lib/maven
export PATH=${PATH}:${M2_HOME}/bin
ln -s /usr/lib/maven/bin/mvn /usr/local/bin
mvn --version
java --version
