# Enforce the manifest-checkable practices at admission

## Root cause pattern

The checklist scores a Deployment after it runs. Nothing stops the next manifest from
bringing back a fixed `-Xmx`, a missing startup probe or a short grace period: the
regression shows only in the next measurement, after it reached the cluster.

## How it works

- A Kyverno [NamespacedValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/)
  holds CEL expressions that Kyverno evaluates on every matching admission request
  (here: Deployments, CREATE and UPDATE) in the policy's own namespace. The team that owns
  the namespace owns its policies, without cluster-admin.
- With `validationActions: [Deny]` a request that makes an expression false is rejected
  with that validation's `message`.
- Kyverno also evaluates existing resources in the background and records the results in a
  PolicyReport in the namespace (`kubectl get policyreport`).
- The rules apply to the app container as the sensor reads it (the container named like the
  Deployment, else the first one). Sidecars keep their own probes and lifecycle.
- Only what the manifest alone decides can be enforced here: items 1, 3, 9 (the probe
  shape) and 10. A `preStop` hook must be a plain sleep, or its duration cannot be checked. Items that need a running pod (sizes against the working set, CPU against
  steady usage, startup time, blocking) stay with the sensor.

## Trade-offs

- The policy checks shape, not fit: it accepts any equal request and limit, sized or not.
- It covers one namespace. Rules for every team belong in a cluster-scoped
  `ValidatingPolicy` (or a native `ValidatingAdmissionPolicy`) that the platform team owns.
- An existing Deployment that breaks a rule keeps running: it shows in the PolicyReport,
  and its next update is denied.

## Artifact

`kyverno-policy.yaml` with `<namespace>` filled, written to the app's `k8s/policy.yaml`.
Keep the expressions verbatim.
