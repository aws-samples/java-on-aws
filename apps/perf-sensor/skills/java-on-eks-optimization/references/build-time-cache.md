# Build-time class caches: CDS and the Java 25 AOT cache

## Introduction

Much of a Java service's startup is spent loading and verifying classes and, for
the JIT, re-profiling the same hot paths every boot. A build-time cache records
that work once and ships it in the image, so every pod start reuses it. Two
options: **CDS** (Class Data Sharing, any modern JDK) and the **AOT cache**
(Java 25, richer — includes AOT-linked classes and profile data).

## How it works

- **CDS / AppCDS**: dump the app + library classes to a shared archive at build
  time; the runtime memory-maps it instead of loading classes from jars.
- **AOT cache (Java 25)**: a two-step build — `-XX:AOTMode=record` runs the app
  through context refresh to capture an AOT configuration, then
  `-XX:AOTMode=create` writes an `.aot` cache. The runtime starts with
  `-XX:AOTCache=…`, skipping most class loading and early JIT.
- Spring Boot supports both; the AOT engine (`-Dspring-boot.aot.enabled=true`)
  pre-computes bean definitions so the cache is effective.

## Key benefits

- Substantial startup reduction with **no application code change** — only the
  build and the launch flags change.
- The image is self-contained; no runtime download or warmup service.
- Composes with in-place CPU boost and right-sizing.

## Trade-offs

- The cache is tied to the classpath and JDK; rebuild it when either changes
  (the golden Dockerfile builds a sorted, deterministic classpath for this reason).
- Training must exercise a representative path; the reference Dockerfile excludes
  DB auto-config when no datasource is provided so training still completes.
- CDS helps class loading; the AOT cache additionally carries linking/profile data,
  so prefer AOT on Java 25.

## Artifact

Use `Dockerfile.aot` verbatim, filling `JAR_FILE` and `MAIN_CLASS` from the app's
`pom.xml` (`build.finalName` → the `-exec.jar`; the Spring Boot main class). Build,
push, `set image`, then verify with `perf-sensor.startupLog` and `measure`
(startup seconds drop) and `profileTop cpu` (JIT share falls).

Immersion Day: Optimize containers → CDS, AOT.
