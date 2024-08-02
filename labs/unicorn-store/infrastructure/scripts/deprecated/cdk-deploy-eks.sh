#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk deploy UnicornStoreSpringEKS --outputs-file target/output-eks.json --require-approval never
popd
