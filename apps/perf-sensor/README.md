# perf-sensor

Deterministic performance sensors for Java workloads on Amazon EKS, exposed to an AI
assistant over MCP (streamable-http) and to an operator over REST. The sensor **measures**;
it never writes to the cluster, never drives traffic and runs no model. Judgement lives in
two Claude Code skills shipped next to it (`skills/`): a twelve-item checklist and an
optimization playbook whose sizing numbers come from `references/sizing-policy.yaml`.

Companion: [`apps/perf-profiler`](../perf-profiler/README.md), the privilege-free sidecar
that gives the sensor thread dumps, the JFR ring and continuous profiles.

## What each part does

| Part | One sentence |
|---|---|
| `measure` | Reads the Deployment and its Ready pods (Kubernetes API), cAdvisor and Micrometer series scoped to those pods (Prometheus), the CPU/wall profile summary (Pyroscope), heap flags and the JFR ring (sidecar `/dump`) and returns typed facts with the window; if the pod is younger than `minUptimeSeconds` it waits up to 30 s per call. |
| `sizeMemory` | `limits = roundUp(max(peak × peakFactor, floor × floorSafetyFactor), roundMi)`, `requests = limits`, 75 % / 50 % heap, SerialGC on ≤ 1 CPU, from the working-set floor and peak of the current pods; BLOCKED unless uptime, profile samples and observed load pass the guard. |
| `sizeCpu` | `requests.cpu = roundUp(p95 CPU usage × cpuFactor, roundMillicores)` capped at the current limit, limit unchanged; same guard. |
| `threadDump` | One JSON thread dump (`jcmd Thread.dump_to_file -format=json`, virtual threads included) from the newest Ready pod, or N pods summed, reduced to counts: request-path threads, those parked in `Future.get`, those blocked inside a transaction, those waiting for a pooled connection, top blocking frames; `null` when no dump could be taken. |
| `diagnoseBlocking` | 40 thread dumps over 20 s while the operator's load runs, reporting peak concurrent counts and summed blocking frames; BLOCKED when the last-minute request rate is below the threshold or no dump can be taken. |
| `profileTop` | Pyroscope's hottest leaf frames by self time for `cpu` or `wall`, with the JIT/GC or futex share of the **whole** profile. |
| `startupLog` | The last `Started … in N seconds` or `Restored …` line from the app container's log, with `kind`. |
| `StartupMetrics` | Every 30 s reads each profiled pod's log once and publishes `perf_sensor_startup_seconds{service,namespace,pod}`, because `application.ready.time` is frozen inside a CRaC checkpoint. |
| REST `/api/v1/*` | The same seven operations for `curl`, so an operator can check a number next to what the assistant saw; `/api/v1/tools` lists them. |

Every number in a tool result names its source; a fact that cannot be read is `null`
(the skills score it UNKNOWN, never PASS or FAIL).

## Contract

- **Naming.** Pyroscope `service_name` = Kubernetes Deployment = namespace = app container
  name. The sidecar sets `service_name` from the pod's `app` label (`SERVICE_LABEL`).
- **Stack.** Spring Boot (the `Started`/`Restored` log line, Micrometer `application`
  tag, `http_server_requests_seconds*`, `application_ready_time_seconds`), HikariCP
  (`ConcurrentBag.borrow` = waiting for a connection), Spring/Jakarta transaction
  interceptors (= "inside a transaction"). Other stacks: extend the marker lists in
  `collect/DumpCollector.java` and the regex in `collect/LogCollector.java`.
- **`REQUEST_PACKAGE` is required.** A thread is "request path" when this package is on
  its stack; the sensor refuses to start without it (`k8s/deployment.yaml`, set by
  `perf-sensor.sh`).
- **Profiled workloads** are discovered by the profiler opt-in label
  (`PROFILED_POD_LABEL`, default `perf-profile/sidecar=true`), so one sensor serves every
  opted-in service in the cluster.

Environment variables are listed in `src/main/resources/application.yaml`.

## Security posture

- Read-only RBAC: `get`/`list` on `deployments`, `pods`, `pods/log` (`k8s/rbac.yaml`); no
  write verbs, no Pod Identity, no AWS calls.
- Pod: non-root (UID 1000), `readOnlyRootFilesystem`, `drop: [ALL]`, `RuntimeDefault`
  seccomp; `/tmp` is an emptyDir for the fetched JFR file.
- Network: ClusterIP only, no Ingress, reached from the IDE over `kubectl port-forward`.
  The sensor's MCP/REST port and the sidecar's `/dump` port are unauthenticated and
  reachable from any pod in the cluster; both are read-only. In a shared cluster, add a
  NetworkPolicy that limits `/dump` (9100) to the sensor and 8080 to Prometheus and the
  operator's path.
- Output hygiene: `jfr.jvmArgs` masks the value of any `-D…password|secret|token|key=`
  flag; thread dumps are summarised, never returned raw.
- Image: `amazoncorretto:25-al2023` via jib, deployed by digest.

## Build, test, deploy

```bash
mvn -o test                                             # 51 unit tests, no cluster needed
infra/scripts/deploy/java-on-amazon-eks/perf-sensor.sh  # build (jib, push, digest) then install (RBAC, Deployment, dashboard); or `build` / `install` alone
infra/scripts/deploy/java-on-amazon-eks/claude-code.sh   # skills + .mcp.json + Claude permissions on the IDE
kubectl -n monitoring port-forward svc/perf-sensor 8090:8080
curl -s localhost:8090/api/v1/measure/<service> | jq .
```

`perf-sensor.sh` takes `APP_NS` and `REQUEST_PACKAGE` for the workload; the Grafana
dashboard is `k8s/dashboard.json`.

## Layout

```
src/main/java/com/example/perf/sensor/
  SensorApplication      Boot + MCP tool registration
  SensorMcpTools         the seven MCP tools (descriptions are the tool contract)
  SensorService          guards, arithmetic, dump aggregation over pods and time
  StartupMetrics         startup gauge for every profiled pod
  api/SensorController   REST mirror of the tools
  collect/               one class per source: K8s, Prometheus, Pyroscope, /dump, JFR, pod log
  facts/                 the typed result records
skills/                  java-on-eks-checklist, java-on-eks-optimization (+ references)
k8s/                     rbac, deployment, dashboard.json
ACCEPTANCE.md            acceptance criteria for a ws-test run of the workshop content
```
