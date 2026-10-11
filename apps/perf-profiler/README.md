# perf-profiler

Privilege-free JVM profiler sidecar. Amazon Corretto 25 +
[async-profiler](https://github.com/async-profiler/async-profiler), baked into one image
(checksum-verified at build; no runtime download). Companion of
[`apps/perf-sensor`](../perf-sensor/README.md), which reads what this sidecar exposes.
A sample for the Java on AWS workshops, not a supported product.

## What each part does

| Part | One sentence |
|---|---|
| `k8s/sidecar-inject-policy.yaml` (Kyverno `MutatingPolicy`) | On pod creation with label `perf-profile/sidecar: "true"`, sets `shareProcessNamespace`, adds a `/perf` emptyDir to the app container and the sidecar (plus `/tmp` for the sidecar), and adds the sidecar container. Only for a supported pod (below) without a sidecar yet and with none of the names, mount path or port the injection adds already in use. |
| `k8s/sidecar-optin-policy.yaml` (Kyverno `ValidatingPolicy`) | Denies an opt-in the sidecar cannot serve, at the apply of the Deployment (autogen covers the pod controllers), with the reason. |
| `profile-loop.sh` (entrypoint) | Finds the app JVM in the shared PID namespace by `libjvm.so` in its memory map (works for a CRaC-restored process), attaches async-profiler (`ctimer` + wall, 10 ms), starts a 10-minute JFR ring (`jcmd JFR.start name=perf maxage=10m`) inside the app JVM, and every 15 s posts the rotated JFR file to Pyroscope under `service_name` = the pod's `app` label. |
| `DumpServer.java` (port 9100) | `GET /dump?kind=threads` → the JSON thread dump (virtual threads included) or 503; `kind=heap` → `GC.heap_info` + `VM.flags`; `kind=jfr` → the JFR ring file; all via `jcmd` on the app JVM, files exchanged through `/perf`. |

The app image is never modified: one label on the pod template opts a workload in and
`kubectl apply` rolls it. Overhead is about 2 %.

## Privileges, exactly

- **Same UID as the app** (`runAsUser: __APP_UID__`, 1000 for the workshop app): JVM
  dynamic attach (`jcmd`, `asprof`) requires the attaching process to have the target's
  UID. No root.
- **`SYS_PTRACE` added, everything else dropped**: what async-profiler's `ctimer` engine
  and `/proc/<pid>/root` access need to reach a sibling process. Neither the `baseline` nor
  the `restricted` [Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
  allows adding `SYS_PTRACE`: an opted-in pod needs a namespace that enforces neither (the
  workshop's app namespace has no Pod Security label) or an exemption.
- `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `RuntimeDefault`
  seccomp, `shareProcessNamespace: true` on the pod; no `privileged`, no `hostPID`.
- Requests equal limits (250m / 384Mi), so injecting the sidecar leaves a Guaranteed pod
  Guaranteed.
- The sidecar copies `libasyncProfiler.so` into `/perf` and the app JVM loads it: the
  sidecar image is trusted code running inside the app's process. Deploy it by digest
  (`perf-profiler.sh` does).

## Deploy

`infra/scripts/deploy/<workshop>/perf-profiler.sh` (java-performance or java-on-amazon-eks; `build`, `install`, or both)
builds and pushes the image, installs Kyverno (chart pinned), and applies the policy with the image pinned by digest,
the cluster name, the app UID (`APP_UID`, default 1000) and the Pyroscope URL substituted.
A supported workload: the **first container is the app**, named like the pod's `app` label
(the container the sensor reads), with **`securityContext.runAsUser` set to `APP_UID`** on the
container or the pod (attach needs the app's UID; the image's `USER` is not visible at
admission). Then opt it in:

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
- In the java-performance and java-on-amazon-eks workshops it replaces the
  `perf-collector` DaemonSet. The java-on-aws workshop still installs perf-collector
  (`infra/scripts/deploy/java-on-aws/6-perf-platform-eks.sh`, `infra/scripts/setup/perf-platform.sh`),
  which runs privileged, as root and with `hostPID`.
