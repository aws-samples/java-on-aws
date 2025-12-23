# Java 25 + Spring Boot 4 Workshop Improvements

---

## Overview: Current vs Improved

### Java 25 / Spring Boot 4 Features

| Feature | Current | Improved |
|---------|---------|----------|
| Virtual Threads | ✅ Enabled | ✅ Keep |
| Spring Boot 4 / Jakarta EE 11 | ✅ Used | ✅ Keep |
| Scoped Values (JEP 506) | ❌ | ✅ Add |
| Flexible Constructors (JEP 513) | ❌ | ✅ Add |
| Sealed Types + Pattern Matching | ❌ | ✅ Add |
| Unnamed Variables (Java 22) | ❌ | ✅ Add |
| Sequenced Collections (Java 21) | ❌ | ✅ Add |
| Compact Object Headers (JEP 519) | ❌ | ✅ Add to Dockerfiles |

### Tests

| Aspect | Current | Improved |
|--------|---------|----------|
| Files | 9 | 4 |
| Assertions | Raw `assert` | AssertJ |
| LocalStack | S3/DynamoDB (wrong) | EventBridge |
| H2 Fallback | Broken | Working |

### Dockerfiles

| File | Current | Improved |
|------|---------|----------|
| 04_optimized_JVM | `--compress 2` deprecated | `--compress zip-6` |
| 05_GraalVM | Wrong name, uses CMD | Rename `05_native`, ENTRYPOINT |
| 06_SOCI | COPY after USER | Fix order |
| 09_CRaC | Uses CMD | ENTRYPOINT |
| 10_async | x64 only, v3.0 | Multi-arch, v4.2.1 |
| All | No Compact Headers | Add `-XX:+UseCompactObjectHeaders` |

---

## 1. Critical Fixes

### 1.1 Update AWS SDK
```xml
<version>2.39.2</version>  <!-- Current: 2.33.4 -->
```

### 1.2 Remove `--add-opens` from surefire
Update test dependencies to eliminate illegal reflective access.

---

## 2. Dockerfile Improvements

### 2.1 File-by-File Fixes

| File | Fix |
|------|-----|
| All | Add `-DskipTests`, use `ENTRYPOINT` not `CMD` |
| 04_optimized_JVM | `--compress 2` → `--compress zip-6` |
| 05_GraalVM | Rename to `05_native` |
| 06_SOCI | Move COPY before USER |
| 10_async | Multi-arch support, update to v4.2.1 |

### 2.2 Add Compact Object Headers
```dockerfile
ENTRYPOINT ["java", "-XX:+UseCompactObjectHeaders", "-jar", ...]
```

### 2.3 ARM64 Support

All Dockerfiles support ARM64 (Graviton) except 10_async which needs this fix:

```dockerfile
ARG TARGETARCH
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x64") && \
    wget .../async-profiler-4.2.1-linux-${ARCH}.tar.gz
```

### 2.4 Proposed Reorganization

```
# SIZE OPTIMIZATION
00_baseline        → 800MB (bad starting point)
01_build           → 700MB (build in docker)
02_multistage      → 400MB (runtime only)
03_custom_jre      → 150MB (jlink)
04_spring_layers   → 400MB (faster rebuilds)
05_native          → 80MB  (Mandrel)

# STARTUP OPTIMIZATION
06_cds             → ~5s   (Class Data Sharing)
07_aot_leyden      → ~2s   (Java 25 Leyden)
08_crac            → ~100ms (Checkpoint/Restore)

# OBSERVABILITY
09_otel            → OpenTelemetry
10_profiler        → Async profiler
```

---

## 3. Test Simplification (9 → 4 files)

### Delete
- `InfrastructureInitializer.java`
- `InitializeInfrastructure.java`
- `InitializeSimpleInfrastructure.java`
- `SimpleInfrastructureInitializer.java`
- `application-test.yaml`

### Rename
- `InitializeTestcontainersInfrastructure.java` → `TestInfrastructure.java`
- `TestcontainersInfrastructureInitializer.java` → `TestInfrastructureInitializer.java`

### Fix TestInfrastructureInitializer.java
```java
.withServices(LocalStackContainer.Service.CLOUDWATCHEVENTS)  // was S3/DynamoDB
.withReuse(true)  // add container reuse
// Remove unused dockerAvailable variable
```

### Fix UnicornControllerTest.java
```java
@TestInfrastructure  // was @InitializeTestcontainersInfrastructure
// Remove @ActiveProfiles("test")

// Replace raw assert with AssertJ
assertThat(u.getId()).isEqualTo(id1);  // was: assert u.getId().equals(id1)
```

### Fix schema.sql
```sql
id VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY  -- was: gen_random_uuid()
```

### Final Structure
```
src/test/java/.../integration/
├── TestInfrastructure.java
├── TestInfrastructureInitializer.java
├── UnicornControllerTest.java
└── StoreApplicationTest.java
```

---

## 4. Java 25 Features to Add

### 4.1 Scoped Values (JEP 506)
```java
public final class RequestContext {
    public static final ScopedValue<String> REQUEST_ID = ScopedValue.newInstance();
}

// In filter
ScopedValue.runWhere(RequestContext.REQUEST_ID, uuid,
    () -> filterChain.doFilter(request, response));
```

### 4.2 Flexible Constructor Bodies (JEP 513)
```java
public Unicorn(String name, String age, String size, String type) {
    if (name == null || name.isBlank()) {
        throw new IllegalArgumentException("Name required");
    }
    this.name = name;
    // ...
}
```

### 4.3 Sealed Types + Pattern Matching
```java
private sealed interface Result permits Success, Failure {}
private record Success(String message) implements Result {}
private record Failure(String error) implements Result {}

return switch (result) {
    case Success(var msg) -> ResponseEntity.ok(msg);
    case Failure(var err) -> ResponseEntity.badRequest().body(err);
};
```

### 4.4 Unnamed Variables (Java 22)
```java
} catch (InterruptedException _) {
    Thread.currentThread().interrupt();
}
```

### 4.5 Sequenced Collections (Java 21)
```java
unicorns.getFirst()  // was: unicorns.get(0)
unicorns.getLast()   // was: unicorns.get(unicorns.size() - 1)
```

---

## 5. JVM Optimizations

### 5.1 Compact Object Headers (JEP 519)
```bash
java -XX:+UseCompactObjectHeaders -jar app.jar  # ~10-15% memory reduction
```

### 5.2 Generational Shenandoah (JEP 521)
```bash
java -XX:+UseShenandoahGC -XX:ShenandoahGCMode=generational -jar app.jar
```

---

## 6. Code Quality

### 6.1 Clean Up Unicorn Model
Remove duplicate accessors - keep only `getId()`, `getName()`, etc. Delete `id()`, `name()`.

### 6.2 Fix Unused Variable
```java
private volatile double blackhole;
blackhole = result;  // prevent dead code elimination
```

---

## Summary

| Priority | Item |
|----------|------|
| **High** | Update AWS SDK 2.39.2+ |
| **High** | Remove --add-opens |
| **High** | Simplify tests 9→4 files |
| **High** | Fix LocalStack services |
| **High** | Add Scoped Values |
| **Medium** | Fix Dockerfile issues |
| **Medium** | Add Compact Object Headers |
| **Medium** | Add Sealed Types |
| **Low** | Unnamed Variables |
| **Low** | Sequenced Collections |
| **Low** | Clean Unicorn model |
