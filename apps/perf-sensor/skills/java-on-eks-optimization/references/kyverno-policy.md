# Enforce the manifest-checkable practices at admission

## Root cause pattern

The checklist scores a Deployment after it runs. Nothing stops the next manifest from
bringing back a fixed `-Xmx`, a missing startup probe or a short grace period: the
regression shows only in the next measurement, after it reached the cluster.

## How it works

- A [ValidatingAdmissionPolicy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
  holds CEL expressions the API server evaluates on every matching request, in process:
  no webhook, no controller to run. A `ValidatingAdmissionPolicyBinding` scopes it (here:
  Deployments in the app namespace) and sets the action (`Deny`).
- A request that makes an expression false is rejected with that validation's `message`.
  `kubectl apply --dry-run=server` runs the same check without persisting anything.
- Only what the manifest alone decides can be enforced here: items 1, 3, 9 (the probe
  shape) and 10. Items that need a running pod (sizes against the working set, CPU against
  steady usage, startup time, blocking) stay with the sensor.

## Trade-offs

- The policy checks shape, not fit: it accepts any equal request and limit, sized or not.
- It applies to new requests. Deployments already in the cluster are checked on their next
  update.
- Kyverno (already in the cluster for the profiler sidecar) can express the same rules and
  adds reporting on existing resources. The native policy needs nothing installed.

## Artifact

`admission-policy.yaml` with `<app>` and `<namespace>` filled, written to the app's
`k8s/admission-policy.yaml`. Keep the expressions verbatim.
