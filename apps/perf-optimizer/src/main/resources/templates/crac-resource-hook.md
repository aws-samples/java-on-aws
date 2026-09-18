## CRaC readiness — UnicornPublisher must close/reopen its EventBridge client

The checkpoint is taken at build time (`-Dspring.context.checkpoint=onRefresh`) while
the app holds an open `EventBridgeAsyncClient` (sockets + Netty threads). Open
file descriptors/sockets cannot be checkpointed, so `UnicornPublisher` must implement
`org.crac.Resource`: close the client `beforeCheckpoint`, recreate it `afterRestore`.
Add the `org.crac:crac` dependency (provided by the Azul Zulu CRaC JDK) and apply:

```java
// src/main/java/com/unicorn/store/data/UnicornPublisher.java
import org.crac.Context;
import org.crac.Core;
import org.crac.Resource;

@Service
public class UnicornPublisher implements Resource {                 // <-- implements Resource

    // ...existing fields...

    @PostConstruct
    public void init() {
        createClient();
        Core.getGlobalContext().register(this);                     // <-- register for CRaC callbacks
    }

    @Override
    public void beforeCheckpoint(Context<? extends Resource> context) {
        if (eventBridgeClient != null) {
            eventBridgeClient.close();                              // release sockets/threads before checkpoint
            eventBridgeClient = null;
        }
    }

    @Override
    public void afterRestore(Context<? extends Resource> context) {
        createClient();                                            // fresh client after restore
    }
}
```

Alternative (no code change): swap in a prebuilt `UnicornPublisher.crac` variant that
already implements `Resource`. The CRaC image will not restore cleanly without one of
these — the `fd` left open at checkpoint fails the restore.
