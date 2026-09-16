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
never modified — you opt in with a label and one `rollout restart`.

## Deploy

`infra/scripts/deploy/java-on-amazon-eks/perf-profiler.sh` builds + pushes the
image, installs Kyverno and metrics-server, and applies the policy (substituting
the ECR image URI). Then, per workload:

```bash
kubectl label deploy/unicorn-store-spring -n unicorn-store-spring perf-profile/sidecar=true --overwrite
kubectl rollout restart deploy/unicorn-store-spring -n unicorn-store-spring
```

## Notes

- **HPA:** the injected sidecar carries a CPU request (`100m`) so a pod-level
  Resource HPA can still compute utilization for the app container.
- **Arch:** built for linux/amd64 (matches the workshop nodes). Bump
  `ASYNC_PROFILER_VERSION` (Docker build arg) to upgrade async-profiler.
- Replaces the retired privileged `perf-collector` DaemonSet.
