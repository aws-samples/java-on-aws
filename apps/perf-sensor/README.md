# perf-sensor

Deterministic performance sensors for Java workloads on Amazon EKS, exposed to an AI
assistant over MCP (streamable-http) and to an operator over REST. The sensor **measures**;
it never writes to the cluster, never drives traffic and runs no model. It also scores the
twelve-item checklist, by evaluating the rules in `checklist-rules.yaml` over those facts.
The explanation lives in two Claude Code skills shipped next to it (`skills/`): the checklist
and an optimization playbook whose sizing numbers come from `references/sizing-policy.yaml`.
A sample for the Java on AWS workshops, not a supported product.

Companion: [`apps/perf-profiler`](../perf-profiler/README.md), the privilege-free sidecar
that gives the sensor thread dumps, the JFR ring and continuous profiles.

## What each part does

| Part | One sentence |
|---|---|
| `measure` | Reads the Deployment and its Ready pods (Kubernetes API), cAdvisor and Micrometer series scoped to those pods (Prometheus), the CPU/wall profile summary (Pyroscope), heap flags and the JFR ring (sidecar `/dump`) and returns typed facts with the window and `jvmFlags` (`-Xmx`/`-Xms` and `ActiveProcessorCount` for the current limits, for a CRaC checkpoint); if the pod is younger than `minUptimeSeconds` it waits up to 30 s per call. |
| `sizeMemory` | `limits = roundUp(max(peak × peakFactor, floor × floorSafetyFactor), roundMi)`, `requests = limits`, 75 % / 50 % heap (and the matching `-Xmx`/`-Xms`), SerialGC on ≤ 1 CPU, from the working-set floor and peak of the current pods; BLOCKED unless uptime, profile samples and observed load pass the guard. |
| `sizeCpu` | `requests.cpu = roundUp(steady CPU (mean minus JIT) × cpuFactor, roundMillicores)` capped at the current limit, limit unchanged, plus the `ActiveProcessorCount` flag for the limit; same guard. |
| `threadDump` | One JSON thread dump (`jcmd Thread.dump_to_file -format=json`, virtual threads included) from the newest Ready pod, or N pods summed, reduced to counts: request-path threads, those parked in `Future.get`, those blocked inside a transaction, those waiting for a pooled connection, top blocking frames; `null` when no dump could be taken. |
| `diagnoseBlocking` | Up to 40 thread dumps over 20 s of the newest Ready pod while the operator's load runs, reporting peak concurrent counts, summed blocking frames, the pod, the dumps tried and taken and the time sampled; BLOCKED when the last-minute request rate is below the threshold, no dump can be taken, or fewer than 80 % succeeded and none showed a block. |
| `profileTop` | Pyroscope's hottest leaf frames by self time for `cpu` or `wall`, with the JIT/GC or futex share of the **whole** profile. |
| `startupLog` | The last `Started … in N seconds` or `Restored …` line from the app container's log, with `kind`. |
| `checklist` | Waits until the current pod is `minUptimeSeconds` old (default 120), runs `measure` and `diagnoseBlocking`, and evaluates `src/main/resources/checklist-rules.yaml` (CEL expressions, the language Kubernetes uses for validation rules: no side effects, no I/O) over the facts: score, one verdict and evidence cell per item, and the markdown table. `CHECKLIST_RULES` points at a replacement file: the deploy script ships the bundled one as the ConfigMap `perf-sensor-checklist-rules` in `monitoring` and mounts it, so `kubectl` shows what is scored. |
| `StartupMetrics` | Every 30 s reads each profiled pod's log once and publishes `perf_sensor_startup_seconds{service,namespace,pod}`, because `application.ready.time` is frozen inside a CRaC checkpoint. |
| REST `/api/v1/*` | The same eight operations for `curl`, so an operator can check a number next to what the assistant saw; `/api/v1/tools` lists them. `/api/v1/checklist/<service>?format=text&wait=true` prints a dot every 5 s while it waits and measures, then the table. |

Every number in a tool result names its source; a fact that cannot be read is `null`
(the checklist scores it UNKNOWN, never PASS or FAIL).

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
- **`SENSOR_SERVICES` is required**: the workloads the sensor answers for, all with the
  request package above. Any other service, and any name that is not a Kubernetes name, is
  refused (REST 400, an MCP tool error): its stacks would never match the package and its
  blocking counts would read 0. For several applications with different packages, run one
  sensor per package.
- **Startup** is published for every pod with the profiler opt-in label
  (`PROFILED_POD_LABEL`, default `perf-profile/sidecar=true`).

Environment variables are listed in `src/main/resources/application.yaml`.

## Security posture

- Read-only RBAC: `get`/`list` on `deployments`, `pods`, `pods/log` (`k8s/rbac.yaml`); no
  write verbs, no Pod Identity, no AWS calls.
- Pod: non-root (UID 1000), `readOnlyRootFilesystem`, `drop: [ALL]`, `RuntimeDefault`
  seccomp; `/tmp` is an emptyDir for the fetched JFR file.
- Network: ClusterIP only, no Ingress, reached from the IDE over `kubectl port-forward`.
  The sensor's MCP/REST port and the sidecar's `/dump` port are unauthenticated and
  reachable from any pod in the cluster; both are read-only, but a thread dump or a JFR
  ring is privileged information. **Before using it in a shared cluster**, apply
  `k8s/networkpolicy.yaml` (only the sensor reaches `/dump`, only Prometheus reaches the
  sensor; needs a CNI that enforces NetworkPolicy) and grant `pods/portforward` on the sensor
  only to its operators. One sensor reads every namespace its ClusterRole allows: for
  isolation between teams, run one sensor per team.
- Tool output is data from the workload (log lines, stack frames, JVM flags, Kubernetes
  object text). The skills treat it as evidence, never as instructions, and every change
  is reviewed before the operator deploys it.
- Output hygiene: `workload.javaToolOptions` and `jfr.jvmArgs` carry only JVM tuning flags
  (`-XX:…`, `-Xmx`, `-Xms`, `-Xss`, `-Xmn`); system properties, agents and any other option
  are dropped, because a credential can sit in any of them. Thread dumps are summarised,
  never returned raw.
- Image: `amazoncorretto:25-al2023` via jib, deployed by digest.

## Build, test, deploy

```bash
mvn -o test                                             # unit tests, no cluster needed
infra/scripts/deploy/java-performance/perf-sensor.sh    # build (jib, push, digest) then install (RBAC, Deployment, dashboard); or `build` / `install` alone
infra/scripts/deploy/java-performance/claude-code.sh     # skills + .mcp.json + Claude permissions on the IDE
kubectl -n monitoring port-forward svc/perf-sensor 8090:8080
curl -s localhost:8090/api/v1/measure/<service> | jq .
curl -sN "localhost:8090/api/v1/checklist/<service>?format=text&wait=true"
```

The java-on-amazon-eks workshop runs the same scripts through wrappers in
`infra/scripts/deploy/java-on-amazon-eks/`. `perf-sensor.sh` takes `APP_NS`, `REQUEST_PACKAGE`
and `SENSOR_SERVICES` for the workload; the Grafana
dashboard is `k8s/dashboard.json`. The java-performance workshop runs as a ws-test, with the
acceptance criteria for the skills: [infra/scripts/ws-test/README.md](../../infra/scripts/ws-test/README.md).

## Layout

```
src/main/java/com/example/perf/sensor/
  SensorApplication      Boot + MCP tool registration
  SensorMcpTools         the eight MCP tools (descriptions are the tool contract)
  SensorService          guards, arithmetic, dump aggregation over pods and time
  StartupMetrics         startup gauge for every profiled pod
  api/SensorController   REST mirror of the tools
  api/ChecklistController REST checklist: json, markdown or text, 503 or progress while the pod settles
  checklist/             the rules engine (CEL) and the checklist service
  collect/               one class per source: K8s, Prometheus, Pyroscope, /dump, JFR, pod log
  facts/                 the typed result records
skills/                  java-on-eks-checklist, java-on-eks-optimization (+ references)
k8s/                     rbac, deployment, dashboard.json, networkpolicy.yaml (shared-cluster boundary, not applied)
```
