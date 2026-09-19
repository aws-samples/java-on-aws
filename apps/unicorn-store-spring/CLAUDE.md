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

Image builds go through **`scripts/build.sh <tag> [dockerfile]`**, which resolves the
ECR repo and the Aurora build-args (SSM `workshop-db-connection-string` + Secrets
Manager `workshop-db-secret`) — no placeholders. It prints the pushed `repo:tag`.

```bash
# Image change (new Dockerfile / source), e.g. tag aot or crac:
IMG=$(./scripts/build.sh aot Dockerfile.aot)     # or: crac Dockerfile.crac | latest
kubectl -n unicorn-store-spring set image deploy/unicorn-store-spring unicorn-store-spring="$IMG"
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring

# Manifest change (resources, resizePolicy, env):
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring   # apply of unchanged :latest is a no-op
kubectl -n unicorn-store-spring rollout status  deploy/unicorn-store-spring
```

## Branch convention

One change per branch: `git checkout -b opt/<short-name>` before editing.
