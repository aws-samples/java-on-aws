# perf-collector

Runs alongside target JVMs on Amazon EKS (DaemonSet) and Amazon ECS
(sidecar). Discovers JVMs whose owning workload is opted in with the
`perf-profile/service` label (EKS) or tag (ECS). Attaches async-profiler
for continuous Pyroscope push. Serves `POST /dump` to capture on-demand
JFR and thread snapshots, uploading them to S3.

The full deployment walkthrough lives in the workshop content at
`content/analysis/perf-platform/collector/`. This README covers build
and the label/tag contract only.

## Fetch runtime binaries

The image bundles `jattach` and `libasyncProfiler.so`. They're not in git —
fetch them before the first `mvn compile jib:build`:

```bash
cd apps/perf-collector
AP_VER=4.3

# jattach (static, same binary works for both arches with a single entrypoint)
curl -L -o src/main/jib/opt/perf-collector/bin/jattach \
  https://github.com/jattach/jattach/releases/latest/download/jattach
chmod +x src/main/jib/opt/perf-collector/bin/jattach

# async-profiler
curl -L https://github.com/async-profiler/async-profiler/releases/download/v${AP_VER}/async-profiler-${AP_VER}-linux-x64.tar.gz \
  | tar -xz -C /tmp
cp /tmp/async-profiler-${AP_VER}-linux-x64/lib/libasyncProfiler.so \
  src/main/jib/opt/perf-collector/async-profiler/libasyncProfiler.so
```

For a multi-arch workshop build repeat with the arm64 tarball and place the
matching `.so` into the image at build time. For a single-arch build the
above is sufficient.

## Build

```bash
mvn compile jib:build -Dimage=${ECR_URI}/perf-collector:latest
```

Multi-arch (`linux/amd64` + `linux/arm64`), Amazon Corretto 25 JRE base.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/dump` | Analyzer trigger. 202 Accepted + async upload to predicted S3 URI. |
| GET | `/actuator/health` | Probe. |
| GET | `/actuator/prometheus` | Metrics. |

## Environment variables

| Name | Required | Description |
|------|----------|-------------|
| `AWS_REGION` | yes | AWS Region for the S3 SDK client. |
| `AWS_S3_BUCKET` | yes | Workshop bucket (SSM `workshop-bucket-name`). |
| `PYROSCOPE_URL` | yes | `http://pyroscope.monitoring:4040` on EKS; internal NLB DNS on ECS. |
| `PERF_COLLECTOR_PLATFORM` | yes | `eks` or `ecs`. Drives which `TargetResolver` bean wakes up. |
| `NODE_NAME` | EKS only | From Downward API (`spec.nodeName`). Limits discovery to pods on own node. |

## Label / tag contract

| Platform | Opt-in marker | Service name source | Version source |
|----------|---------------|---------------------|----------------|
| EKS | pod label `perf-profile/service=<name>` | label value | `app.kubernetes.io/version` or container image tag |
| ECS | task tag `perf-profile:service=<name>` | tag value | app container image tag |

Missing marker → workload is ignored entirely. No profiler attach, no
Pyroscope samples, no footprint.

## Deployment

See the workshop content page for the full DaemonSet and task-definition
manifests, Pod Identity binding, and capability requirements.
Key invariants:

- EKS DaemonSet: `hostPID: true` + `SYS_PTRACE` capability.
- ECS task: `pidMode: task` + sidecar `linuxParameters.capabilities.add: ["SYS_PTRACE"]`.
- IAM: `perf-collector-eks-pod-role` (EKS) or `perf-collector-ecs-task-role`
  (ECS), both provisioned by the `PerfPlatform.java` CDK construct.
