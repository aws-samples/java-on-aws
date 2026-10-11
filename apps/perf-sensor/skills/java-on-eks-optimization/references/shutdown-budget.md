# Shutdown budget for a Java service on EKS

## Root cause pattern

A Deployment with a `preStop` sleep and the default `terminationGracePeriodSeconds`
(30 s), running an app with graceful shutdown. The grace period does not cover the
`preStop` sleep plus the app's drain, so every rollout or scale-in can kill the process
while it still finishes requests (checklist item 10).

## How it works

- When a pod is deleted, the kubelet runs the `preStop` hook, then sends SIGTERM, and sends
  SIGKILL when the grace period expires. The grace period counts from the start of
  `preStop`, so the sleep uses part of it. Default 30 s.
  ([Kubernetes: Pod termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination))
- At the same time the endpoint is marked terminating. The AWS Load Balancer Controller
  (target type `ip`) sees that and deregisters the pod IP from the ALB, which can take a
  while, so new requests still arrive after deletion starts. The `preStop` sleep delays
  SIGTERM until the ALB stops sending them.
  ([EKS best practices: Load balancing](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html#_gracefully_handle_the_client_requests))
- On SIGTERM, Spring Boot graceful shutdown stops accepting new requests and lets in-flight
  ones finish for up to `spring.lifecycle.timeout-per-shutdown-phase`, 30 s when unset.
  ([Spring Boot: Graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html))
- Budget: `terminationGracePeriodSeconds = preStopSleepSeconds + timeout-per-shutdown-phase`.

## Trade-offs

- A longer grace period makes rollouts and node drains slower only when the app actually
  needs the time: the pod ends as soon as the process exits.
- Lowering `timeout-per-shutdown-phase` instead shortens the budget but cuts long requests.

## Artifact

`terminationGracePeriodSeconds` under `spec.template.spec` of the app's
`k8s/deployment.yaml`, set to the budget above. Cite the `preStop` seconds and the timeout
you read (or the 30 s default).
