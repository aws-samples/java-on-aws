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

Under-load facts (memory peak, CPU p95, throttling, blocked request threads, request
latency) exist only while requests flow. The service does not generate its own traffic;
`scripts/load.sh` does: it drives `POST /unicorns` at 50 req/s for 120 s against the
service's Ingress and returns after 90 s with ~30 s of load still flowing — measure right
after it returns. Run it when a measurement needs load and the current request rate is
below 1 req/s (probe traffic alone is ≈ 0.5 req/s); once per question is enough, and not
while a run is already flowing. Invoke it by its path from the current directory, e.g.
`unicorn-store-spring/scripts/load.sh` — no `cd`, no other command chained to it.
