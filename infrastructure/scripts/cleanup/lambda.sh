echo Deleting Lambda ...
cd ~/environment/unicorn-store-audit
sam delete --stack-name unicorn-audit-stack --no-prompts
aws events delete-rule --name unicorn-event-rule
aws cloudformation delete-stack --stack-name aws-sam-cli-managed-default
