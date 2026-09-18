# unicorn-store-spring — optimization loop (Claude Code + perf-optimizer)

Spring Boot 4.1 / Amazon Corretto 25 service on EKS (namespace **`unicorn-store-spring`**,
Deployment/Service/container all named `unicorn-store-spring`). You optimize it by
asking the **perf-optimizer** MCP server for findings and applying them here.

## File map

- `src/main/java/com/unicorn/store/…` — app code
  - `service/UnicornService.java` — request logic (event publish on create/update/delete)
  - `data/UnicornPublisher.java` — EventBridge async publisher
- `src/main/resources/application.yaml` — Spring config (datasource/Hikari, actuator)
- `Dockerfile` — app image (plain JVM). Golden AOT/CRaC Dockerfiles come from the optimizer.
- `k8s/deployment.yaml` — the Deployment (resources, env, probes). **This is what most fixes patch.**
- `k8s/service.yaml`, `k8s/ingress.yaml`, `k8s/hpa.yaml` — networking / autoscaling (hpa if present)

## The MCP server

`.mcp.json` registers `perf-optimizer` over SSE at `http://localhost:8080/sse`. Start the
port-forward first:

```bash
kubectl -n monitoring port-forward svc/perf-optimizer 8080:8080
```

Tools: `measure <service>`, `analyze <service> [windowMinutes] [explain]`,
`explain <service> <findingId>`. The service name is always `unicorn-store-spring`.

## Build & deploy (only when applying a fix)

Image builds go through **`scripts/build.sh <tag> [dockerfile]`**, which resolves the
ECR repo and the Aurora build-args (SSM `workshop-db-connection-string` + Secrets
Manager `workshop-db-secret`) — no placeholders. It prints the pushed `repo:tag`.

```bash
# Image changes (new Dockerfile / source): save the explain artifact as
# Dockerfile.crac (or Dockerfile.aot), then:
IMG=$(./scripts/build.sh crac)        # or: aot | latest
kubectl -n unicorn-store-spring set image deploy/unicorn-store-spring unicorn-store-spring="$IMG"
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring

# Manifest changes (resources, resizePolicy, HPA):
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring   # apply of unchanged :latest is a no-op
kubectl -n unicorn-store-spring rollout status  deploy/unicorn-store-spring
```

The optimizer detects the applied technique from the **image tag** (`:crac` / `:aot`),
so `set image` to a `:crac` tag is what flips `startup-checkpointable` to RESOLVED on
re-analyze.

## Rules (follow exactly)

1. **Analyze first.** Run `analyze unicorn-store-spring` before proposing any change. Never
   optimize from memory or assumptions.
2. **Never invent values.** Use ONLY the requests/limits, GC flags, image tags, and artifacts
   the optimizer returns. Do not add or change a flag, tag, size, or capability that is not in
   the tool output. (Sizes are computed from measured facts — they are not yours to adjust.)
3. **One finding, one branch.** `git checkout -b opt/<finding-id>` before editing.
4. **Show the diff and ask.** Present the `git diff` and wait for confirmation before
   `kubectl apply` / building an image. Touch only the file(s) the finding lists.
5. **Re-analyze after applying.** Once the rollout is complete, run `analyze unicorn-store-spring`
   again and report the finding as **RESOLVED** with its measured before→after delta.
6. **Respect BLOCKED.** If sizing findings are `BLOCKED` (profiling window not warm), warm the
   app up + apply a little load, then re-analyze — do not force a change.
7. The optimizer is **read-only** on the cluster; all writes (apply/build/rollout) happen here.
