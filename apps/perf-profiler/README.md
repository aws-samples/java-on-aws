# perf-profiler

Privilege-free JVM profiler sidecar for the CON405 workshop. Amazon Corretto 25 +
[async-profiler](https://github.com/async-profiler/async-profiler), baked into one
image — no runtime download.

## How it works

A [Kyverno](https://kyverno.io) `MutatingPolicy` (`k8s/sidecar-inject-policy.yaml`)
watches for Pods labelled `perf-profile/sidecar: "true"`. On admission it:

- sets `shareProcessNamespace: true` on the Pod, and
- injects a `perf-profiler` container from this image with only the `SYS_PTRACE`
  capability (no `privileged`, no `hostPID`).

The sidecar (`profile-loop.sh`, the image ENTRYPOINT) finds the app JVM in the
shared PID namespace, attaches async-profiler's `ctimer` (privilege-free CPU) +
`wall` engines, and pushes rotated JFR recordings to Pyroscope. The app image is
never modified — you opt in with one declarative label on the workload's pod
template.

## On-demand `/dump` endpoint

The sidecar also runs a tiny HTTP server (`DumpServer.java`, JDK 25 single-file
source mode) on **port 9100** (exposed as `containerPort` by the inject policy):

- `GET /dump?kind=threads` → `jcmd <pid> Thread.print -e`
- `GET /dump?kind=heap` → `jcmd <pid> GC.heap_info` + `VM.flags`
- `GET /dump?kind=jfr` → `jcmd <pid> JFR.dump` (best-effort)

`jcmd` targets the app JVM across the shared PID namespace (root + `SYS_PTRACE`),
with `JAVA_TOOL_OPTIONS` nulled per call so the app's flags don't contaminate the
output. `perf-optimizer` reads this via the pod IP to build ThreadFacts/heap — no
collector, no `kubectl exec`.

## Deploy

`infra/scripts/deploy/java-on-amazon-eks/perf-profiler.sh` builds + pushes the
image, installs Kyverno and metrics-server, and applies the policy (substituting
the ECR image URI). Then opt a workload in by adding the label to its pod
template (`spec.template.metadata.labels`) in the deployment manifest and
re-applying — declarative, so it survives redeploys and GitOps reconciliation:

```yaml
# unicorn-store-spring/k8s/deployment.yaml
spec:
  template:
    metadata:
      labels:
        app: unicorn-store-spring
        perf-profile/sidecar: "true"   # opt in
```

```bash
kubectl apply -f unicorn-store-spring/k8s/deployment.yaml   # template change rolls the pods; sidecar injects on the new Pods
```

## Notes

- **HPA:** the injected sidecar carries a CPU request (`100m`) so a pod-level
  Resource HPA can still compute utilization for the app container.
- **Arch:** built for linux/amd64 (matches the workshop nodes). Bump
  `ASYNC_PROFILER_VERSION` (Docker build arg) to upgrade async-profiler.
- Replaces the retired privileged `perf-collector` DaemonSet.
