#bin/sh

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk deploy UnicornStoreSpringCI --outputs-file target/output-ci.json --require-approval never

cd ~/environment/unicorn-store-spring/
git init -b main
git remote add origin codecommit://unicorn-store-spring
git remote -v

git add .
git commit -m "initial commit"
git push --set-upstream origin main

popd
