Notes and cost warnings

- AWS EKS control plane is NOT free: there is a per-cluster hourly fee (~$0.10/hr at time of writing). This will incur charges beyond the Free Tier.
- EC2 Free Tier covers t2.micro for 750 hours/month for 12 months for new accounts; node groups with larger instance types will incur costs.
- IAM, EBS, NAT gateway, data transfer, and other resources may also add charges.

If you need a fully free local Kubernetes experience, consider `kind` or `minikube` instead of EKS.
