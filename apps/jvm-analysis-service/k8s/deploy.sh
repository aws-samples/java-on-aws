S3_BUCKET=$(aws ssm get-parameter --name unicornstore-lambda-bucket-name --query 'Parameter.Value' --output text)
kubectl apply -f deployment.yaml
kubectl wait deployment jvm-analysis-service -n monitoring --for condition=Available=True --timeout=120s
sleep 15
kubectl logs $(kubectl get pods -n monitoring -l app=jvm-analysis-service --field-selector=status.phase=Running -o json | jq -r '.items[0].metadata.name') -n monitoring
