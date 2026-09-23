# Starting point of the java-on-amazon-eks workshop

The files `app-prepare.sh` lays over the participant's copy of
`apps/unicorn-store-spring` to produce the "Starting point: containerized + deployed
to EKS" commit. They are the end state of the immersion-day pages "Containerize and
run" (multi-stage Dockerfile) and "Amazon EKS" (namespace, Pod Identity, secrets via
the Secrets Store CSI driver, Deployment, Service, Ingress), with two adjustments the
workshop needs from the first measurement on: no probe `initialDelaySeconds` (the
startup probe's `failureThreshold x periodSeconds` is the budget) and Prometheus
scrape annotations on the pod template.

`__ECR_URI__` is replaced with the account's repository URI at prepare time.
