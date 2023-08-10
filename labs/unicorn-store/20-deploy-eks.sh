#bin/sh

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk deploy UnicornStoreSpringEKS --outputs-file target/output-eks.json --require-approval never
popd
