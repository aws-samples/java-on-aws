CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)

if ! aws eks list-pod-identity-associations --cluster-name $CLUSTER_NAME --query "associations[?serviceAccount=='jvm-analysis-service' && namespace=='monitoring']" --output text | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name $CLUSTER_NAME \
        --namespace monitoring \
        --service-account jvm-analysis-service \
        --role-arn $(aws iam get-role --role-name jvm-analysis-service-eks-pod-role --query 'Role.Arn' --output text)
fi
sleep 15
