# CRaC: sub-second startup by checkpoint/restore

## Introduction

CRaC (Coordinated Restore at Checkpoint) captures a fully warmed-up JVM — classes
loaded, JIT compiled, context refreshed — as a checkpoint at build time, then
**restores** from it at runtime. Startup drops from seconds to well under a second
because there is no cold start: the process resumes where the checkpoint left off.

## How it works

- The build takes the checkpoint with the **Warp** engine
  (`-XX:CRaCEngine=warp`), which needs no CRIU and no extra container privileges.
- Spring checkpoints on context refresh (`-Dspring.context.checkpoint=onRefresh`),
  so the snapshot is a ready-to-serve application.
- At runtime, `-XX:CRaCRestoreFrom=…` restores the image.

## Add the `org.crac` dependency

CRaC hooks use the `org.crac` API, which the app does not depend on by default. Add
it to `pom.xml` first (Maven; Gradle is analogous):

```xml
<dependency>
    <groupId>org.crac</groupId>
    <artifactId>crac</artifactId>
    <version>1.5.0</version>
</dependency>
```

## The Resource-hook rule

Open file descriptors and sockets **cannot** be checkpointed. **Any class holding a
network client, connection, or file handle** at checkpoint time must implement
`org.crac.Resource`: release the resource in `beforeCheckpoint`, recreate it in
`afterRestore`. Miss one and the restore fails on the open FD (the build enables
`-Djdk.crac.collect-fd-stacktraces=true` so it fails loudly and names the culprit).

```java
import org.crac.Context;
import org.crac.Core;
import org.crac.Resource;

@Service
public class SomeClient implements Resource {   // any class holding sockets/fds
    @PostConstruct
    public void init() {
        openClient();
        Core.getGlobalContext().register(this);  // register for CRaC callbacks
    }
    @Override public void beforeCheckpoint(Context<? extends Resource> ctx) {
        closeClient();                           // release sockets/threads before checkpoint
    }
    @Override public void afterRestore(Context<? extends Resource> ctx) {
        openClient();                            // fresh client after restore
    }
}
```

Scan `src/` for every class that opens a client/connection/file and add a hook to each.

## Key benefits

- The fastest startup available — sub-second — ideal for scale-to-zero and fast
  scale-up.
- The restored process is already warm: no JIT ramp, no cold-cache latency spike.

## Gotcha: JVM flags live in the checkpoint, not in the Deployment

GC and heap flags are **baked into the checkpoint** and cannot change at restore. If
the deployment carries `JAVA_TOOL_OPTIONS` from an earlier right-sizing step
(e.g. `-XX:+UseSerialGC -XX:MaxRAMPercentage=75`), the restoring JVM re-reads it,
finds a flag it may not change after checkpoint, and **crash-loops** (e.g. "cannot
change GC after restore"). When switching a workload to the CRaC image, **remove
`JAVA_TOOL_OPTIONS`** (or at least the GC/heap flags) from the Deployment. Keep the
memory `requests`/`limits`; only the JVM-flag env must go.

Consequences to state explicitly:
- `Dockerfile.crac` sets `-XX:+UseSerialGC` on the checkpoint command, so the GC still
  fits a ≤ 1 vCPU pod after restore.
- The heap ceiling (`MaxHeapSize`) is fixed at checkpoint time from the **build**
  container, not from the pod's memory limit. `MaxRAMPercentage` in the Deployment has
  no effect on a restored JVM. If the heap ceiling must match the pod, take the
  checkpoint in a container with the same memory limit or pass an explicit `-Xmx` on
  the checkpoint command. This is a CRaC trade-off, not a misconfiguration.

## Trade-offs

- **Credentials at restore**: a client closed before checkpoint must fetch fresh
  credentials/config in `afterRestore` — do not bake secrets into the checkpoint.
- Requires a CRaC-enabled JDK (e.g. Azul Zulu CRaC) and the `org.crac` API.
- Every FD-holding class needs a hook; missing one breaks restore.
- The checkpoint is environment-sensitive; rebuild it when the app or JDK changes.

## Artifact

Three changes: (1) add the `org.crac` dependency to `pom.xml`; (2) add an
`org.crac.Resource` hook to each FD-holding class found in `src/`; (3) use
`Dockerfile.crac` verbatim, filling `JAR_FILE` from the app's `pom.xml`. Verify with
`perf-sensor.startupLog` — `kind` should read **Restored** and seconds < 1.


