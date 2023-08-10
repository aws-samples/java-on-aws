#bin/sh

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk deploy UnicornStoreSpringECS --outputs-file target/output-ecs.json --require-approval never
popd
