# perf-profiler

Privilege-free JVM profiler sidecar. Amazon Corretto 25 +
[async-profiler](https://github.com/async-profiler/async-profiler), baked into one image
(checksum-verified at build; no runtime download). Companion of
[`apps/perf-sensor`](../perf-sensor/README.md), which reads what this sidecar exposes.

## What each part does

| Part | One sentence |
|---|---|
| `k8s/sidecar-inject-policy.yaml` (Kyverno `MutatingPolicy`) | On pod creation with label `perf-profile/sidecar: "true"`, sets `shareProcessNamespace`, adds a `/perf` emptyDir to the app container and the sidecar (plus `/tmp` for the sidecar), and adds the sidecar container. |
| `profile-loop.sh` (entrypoint) | Finds the app JVM in the shared PID namespace by `libjvm.so` in its memory map (works for a CRaC-restored process), attaches async-profiler (`ctimer` + wall, 10 ms), starts a 10-minute JFR ring (`jcmd JFR.start name=perf maxage=10m`) inside the app JVM, and every 15 s posts the rotated JFR file to Pyroscope under `service_name` = the pod's `app` label. |
| `DumpServer.java` (port 9100) | `GET /dump?kind=threads` → the JSON thread dump (virtual threads included) or 503; `kind=heap` → `GC.heap_info` + `VM.flags`; `kind=jfr` → the JFR ring file; all via `jcmd` on the app JVM, files exchanged through `/perf`. |

The app image is never modified: one label on the pod template opts a workload in and
`kubectl apply` rolls it. Overhead is about 2 %.

## Privileges, exactly

- **Same UID as the app** (`runAsUser: __APP_UID__`, 1000 for the workshop app): JVM
  dynamic attach (`jcmd`, `asprof`) requires the attaching process to have the target's
  UID. No root.
- **`SYS_PTRACE` added, everything else dropped**: what async-profiler's `ctimer` engine
  and `/proc/<pid>/root` access need to reach a sibling process.
- `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `RuntimeDefault`
  seccomp, `shareProcessNamespace: true` on the pod; no `privileged`, no `hostPID`.
- Requests equal limits (250m / 384Mi), so injecting the sidecar leaves a Guaranteed pod
  Guaranteed.
- The sidecar copies `libasyncProfiler.so` into `/perf` and the app JVM loads it: the
  sidecar image is trusted code running inside the app's process. Deploy it by digest
  (`perf-profiler.sh` does).

## Deploy

`infra/scripts/deploy/java-on-amazon-eks/perf-profiler.sh` (`build`, `install`, or both)
builds and pushes the image, installs Kyverno (chart pinned), and applies the policy with the image pinned by digest,
the cluster name, the app UID (`APP_UID`, default 1000) and the Pyroscope URL substituted.
Then opt a workload in:

```yaml
# <app>/k8s/deployment.yaml
spec:
  template:
    metadata:
      labels:
        app: <app>
        perf-profile/sidecar: "true"   # opt in
```

```bash
kubectl apply -f <app>/k8s/deployment.yaml   # the pod-template change rolls the pods; the new ones carry the sidecar
kubectl get pod -l app=<app> -o jsonpath='{.items[0].spec.containers[*].name}'   # <app> perf-profiler
```

`failurePolicy: Ignore` on the policy means a Kyverno outage yields an un-profiled pod
rather than a blocked rollout; check the container list after the first apply.

## Notes

- Arch: linux/amd64 (the workshop nodes). To upgrade async-profiler, bump
  `ASYNC_PROFILER_VERSION` **and** `ASYNC_PROFILER_SHA256` in the Dockerfile.
- `PERF_DIR` (default `/perf`) is where the app JVM writes and the sidecar reads; without
  the volume the sidecar falls back to the target's `/tmp` through `/proc/<pid>/root`.
- Replaces the retired privileged `perf-collector` DaemonSet.
