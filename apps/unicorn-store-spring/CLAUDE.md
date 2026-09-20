# unicorn-store-spring

Spring Boot 4.1 / Amazon Corretto 25 service on EKS. Namespace, Deployment,
Service and app container are all named **`unicorn-store-spring`**.

This file describes how *this app* is built and deployed. How to optimize a Java
service on EKS (techniques, sizing, golden Dockerfiles) lives in the
`java-on-eks-optimization` skill, not here.

## File map

- `src/main/java/com/unicorn/store/…` — app code
  - `service/UnicornService.java` — request logic (event publish on create/update/delete)
  - `data/UnicornPublisher.java` — EventBridge async publisher
- `src/main/resources/application.yaml` — Spring config (datasource/Hikari, actuator)
- `pom.xml` — `artifactId` `store-spring`, `version` `1.0.0`; the executable jar is
  `store-spring-1.0.0-exec.jar`; main class `com.unicorn.store.StoreApplication`
- `Dockerfile` — app image (plain JVM)
- `k8s/deployment.yaml` — the Deployment (resources, env, probes) — what most manifest changes patch
- `k8s/service.yaml`, `k8s/ingress.yaml` — networking

## Build & deploy

**`k8s/deployment.yaml` is the single source of truth.** Image, resources, env, and
probes all live in that file — change them there and apply the file. Do **not** use
`kubectl set image` / `set env` / `patch` for lasting changes: they mutate the live
object only, so the next `apply -f` reverts them (the file wins) and silently undoes
your image or flag change. One file, one `apply`, no drift.

Image builds go through **`scripts/build.sh <tag> [dockerfile]`**, which resolves the
ECR repo and the Aurora build-args (SSM `workshop-db-connection-string` + Secrets
Manager `workshop-db-secret`) — no placeholders. It prints the pushed `repo:tag`.

```bash
# 1. Build (only when the image changes — new Dockerfile / source):
IMG=$(./scripts/build.sh <tag> <Dockerfile>)     # e.g. ./scripts/build.sh latest

# 2. Edit k8s/deployment.yaml: set the container image to "$IMG" (if built) and make
#    any resources / env / resizePolicy changes in the SAME file.
#    (image lives at spec.template.spec.containers[0].image)

# 3. Apply the file and wait:
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring
```

Removing an env var (e.g. dropping `JAVA_TOOL_OPTIONS` for a CRaC image) is a manifest
edit too — delete it from the file and apply, don't `set env`.
