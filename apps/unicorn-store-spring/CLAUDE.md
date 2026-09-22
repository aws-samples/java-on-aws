# unicorn-store-spring

Spring Boot 4.1 / Amazon Corretto 25 service on EKS. Namespace, Deployment,
Service and app container are all named **`unicorn-store-spring`**.

## File map

- `src/main/java/com/unicorn/store/…` — app code
  - `service/UnicornService.java` — request logic (event publish on create/update/delete)
  - `data/UnicornPublisher.java` — EventBridge async publisher
- `src/main/resources/application.yaml` — Spring config (datasource/Hikari, actuator)
- `pom.xml` — `artifactId` `store-spring`, `version` `1.0.0`; the executable jar is
  `store-spring-1.0.0-exec.jar`; main class `com.unicorn.store.StoreApplication`
- `Dockerfile` — app image (plain JVM)
- `k8s/deployment.yaml` — the Deployment (image, resources, env, probes)
- `k8s/service.yaml`, `k8s/ingress.yaml` — networking
- `scripts/build.sh <tag> [Dockerfile]` — build + push an image to the service's ECR repo
- `scripts/load.sh` — load-test the deployed service (see below)

## Deployment

**`k8s/deployment.yaml` is the single source of truth.** Image, resources, env and
probes live in that file — change them there. Never `kubectl set image` / `set env` /
`patch`: they change the live object only and the next `apply -f` reverts them.

Building (`scripts/build.sh`), applying the manifest and committing are the developer's
steps, done after a change has been reviewed.

## Load

`scripts/load.sh [duration] [rate]` drives `POST /unicorns` against the service's Ingress
(default 50 req/s for 120 s). Under-load measurements (memory peak, CPU p95, throttling,
blocked request threads, request latency) are only meaningful while it runs; keep it running
in its own terminal for as long as the service should be treated as in production
(`while true; do ./scripts/load.sh 600 50; done`). Probe traffic alone is ≈ 0.5 req/s.
