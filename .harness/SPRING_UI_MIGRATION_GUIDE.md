# Spring Boot UI Migration Guide

This guide provides step-by-step instructions to add a web UI to the `unicorn-store-spring` application and migrate from the Jakarta/WildFly version to Spring Boot while reusing existing Harness infrastructure.

## Overview

| Current | Target |
|---------|--------|
| `unicorn-store-jakarta` (WildFly + JSF/PrimeFaces) | `unicorn-store-spring` (Spring Boot + Thymeleaf/HTMX) |
| ~55s startup, ~500MB+ memory | ~5-15s startup, ~256-384MB memory |
| Full app server overhead | Embedded Tomcat, lightweight |

---

## Part 1: Add Web UI to Spring Boot Application

### Step 1.1: Add Thymeleaf and WebJars Dependencies

**File:** `apps/unicorn-store-spring/pom.xml`

Add these dependencies inside the `<dependencies>` section:

```xml
<!-- Thymeleaf for server-side rendering -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-thymeleaf</artifactId>
</dependency>

<!-- Bootstrap CSS/JS via WebJars -->
<dependency>
    <groupId>org.webjars</groupId>
    <artifactId>bootstrap</artifactId>
    <version>5.3.3</version>
</dependency>

<!-- HTMX for dynamic updates without full page reload -->
<dependency>
    <groupId>org.webjars.npm</groupId>
    <artifactId>htmx.org</artifactId>
    <version>1.9.10</version>
</dependency>

<!-- WebJars locator for version-agnostic paths -->
<dependency>
    <groupId>org.webjars</groupId>
    <artifactId>webjars-locator-core</artifactId>
    <version>0.58</version>
</dependency>
```

### Step 1.2: Create Web Controller

**File:** `apps/unicorn-store-spring/src/main/java/com/unicorn/store/controller/WebController.java`

```java
package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

@Controller
@RequestMapping("/webui")
public class WebController {

    private final UnicornService unicornService;

    public WebController(UnicornService unicornService) {
        this.unicornService = unicornService;
    }

    @GetMapping
    public String index(Model model) {
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        model.addAttribute("newUnicorn", new Unicorn());
        return "unicorns";
    }

    @GetMapping("/list")
    public String listUnicorns(Model model) {
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @PostMapping("/create")
    public String createUnicorn(@ModelAttribute Unicorn unicorn, Model model) {
        unicornService.createUnicorn(unicorn);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @GetMapping("/edit/{id}")
    public String editForm(@PathVariable String id, Model model) {
        model.addAttribute("unicorn", unicornService.getUnicorn(id));
        return "fragments/edit-form :: editForm";
    }

    @PostMapping("/update/{id}")
    public String updateUnicorn(@PathVariable String id, @ModelAttribute Unicorn unicorn, Model model) {
        unicornService.updateUnicorn(unicorn, id);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @DeleteMapping("/delete/{id}")
    public String deleteUnicorn(@PathVariable String id, Model model) {
        unicornService.deleteUnicorn(id);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }
}
```

### Step 1.3: Create Main Template

**File:** `apps/unicorn-store-spring/src/main/resources/templates/unicorns.html`

```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Unicorn Store</title>
    <link rel="stylesheet" th:href="@{/webjars/bootstrap/css/bootstrap.min.css}">
    <script th:src="@{/webjars/htmx.org/dist/htmx.min.js}"></script>
    <style>
        .htmx-indicator { display: none; }
        .htmx-request .htmx-indicator { display: inline-block; }
    </style>
</head>
<body>
    <div class="container mt-4">
        <h1 class="mb-4">🦄 Unicorn Store</h1>
        
        <!-- Create Form -->
        <div class="card mb-4">
            <div class="card-header">Add New Unicorn</div>
            <div class="card-body">
                <form hx-post="/webui/create" hx-target="#unicorn-table" hx-swap="innerHTML">
                    <div class="row g-3">
                        <div class="col-md-3">
                            <input type="text" class="form-control" name="name" placeholder="Name" required>
                        </div>
                        <div class="col-md-2">
                            <input type="text" class="form-control" name="age" placeholder="Age">
                        </div>
                        <div class="col-md-2">
                            <input type="text" class="form-control" name="size" placeholder="Size">
                        </div>
                        <div class="col-md-3">
                            <input type="text" class="form-control" name="type" placeholder="Type" required>
                        </div>
                        <div class="col-md-2">
                            <button type="submit" class="btn btn-success w-100">
                                <span class="htmx-indicator spinner-border spinner-border-sm"></span>
                                Add
                            </button>
                        </div>
                    </div>
                </form>
            </div>
        </div>

        <!-- Unicorn Table -->
        <div class="card">
            <div class="card-header">Unicorns</div>
            <div class="card-body">
                <div id="unicorn-table">
                    <div th:replace="~{fragments/unicorn-table :: unicornTable}"></div>
                </div>
            </div>
        </div>

        <!-- Edit Modal -->
        <div class="modal fade" id="editModal" tabindex="-1">
            <div class="modal-dialog">
                <div class="modal-content">
                    <div class="modal-header">
                        <h5 class="modal-title">Edit Unicorn</h5>
                        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                    </div>
                    <div class="modal-body" id="edit-form-container">
                        <!-- Edit form loaded via HTMX -->
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script th:src="@{/webjars/bootstrap/js/bootstrap.bundle.min.js}"></script>
    <script>
        // Show modal when edit form is loaded
        document.body.addEventListener('htmx:afterSwap', function(evt) {
            if (evt.detail.target.id === 'edit-form-container') {
                new bootstrap.Modal(document.getElementById('editModal')).show();
            }
        });
        // Hide modal and refresh table after update
        document.body.addEventListener('htmx:afterRequest', function(evt) {
            if (evt.detail.elt.id === 'edit-form') {
                bootstrap.Modal.getInstance(document.getElementById('editModal')).hide();
            }
        });
    </script>
</body>
</html>
```

### Step 1.4: Create Table Fragment

**File:** `apps/unicorn-store-spring/src/main/resources/templates/fragments/unicorn-table.html`

```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<body>
<div th:fragment="unicornTable">
    <table class="table table-striped table-hover" th:if="${not #lists.isEmpty(unicorns)}">
        <thead class="table-dark">
            <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Age</th>
                <th>Size</th>
                <th>Type</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            <tr th:each="unicorn : ${unicorns}">
                <td th:text="${unicorn.id}"></td>
                <td th:text="${unicorn.name}"></td>
                <td th:text="${unicorn.age}"></td>
                <td th:text="${unicorn.size}"></td>
                <td th:text="${unicorn.type}"></td>
                <td>
                    <button class="btn btn-sm btn-primary"
                            hx-get th:hx-get="@{/webui/edit/{id}(id=${unicorn.id})}"
                            hx-target="#edit-form-container"
                            hx-swap="innerHTML">
                        Edit
                    </button>
                    <button class="btn btn-sm btn-danger"
                            hx-delete th:hx-delete="@{/webui/delete/{id}(id=${unicorn.id})}"
                            hx-target="#unicorn-table"
                            hx-swap="innerHTML"
                            hx-confirm="Are you sure you want to delete this unicorn?">
                        Delete
                    </button>
                </td>
            </tr>
        </tbody>
    </table>
    <div th:if="${#lists.isEmpty(unicorns)}" class="alert alert-info">
        No unicorns found. Add one above!
    </div>
</div>
</body>
</html>
```

### Step 1.5: Create Edit Form Fragment

**File:** `apps/unicorn-store-spring/src/main/resources/templates/fragments/edit-form.html`

```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<body>
<form th:fragment="editForm" id="edit-form"
      th:hx-post="@{/webui/update/{id}(id=${unicorn.id})}"
      hx-target="#unicorn-table"
      hx-swap="innerHTML">
    <div class="mb-3">
        <label class="form-label">Name</label>
        <input type="text" class="form-control" name="name" th:value="${unicorn.name}" required>
    </div>
    <div class="mb-3">
        <label class="form-label">Age</label>
        <input type="text" class="form-control" name="age" th:value="${unicorn.age}">
    </div>
    <div class="mb-3">
        <label class="form-label">Size</label>
        <input type="text" class="form-control" name="size" th:value="${unicorn.size}">
    </div>
    <div class="mb-3">
        <label class="form-label">Type</label>
        <input type="text" class="form-control" name="type" th:value="${unicorn.type}" required>
    </div>
    <div class="d-flex justify-content-end gap-2">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
        <button type="submit" class="btn btn-primary">Save Changes</button>
    </div>
</form>
</body>
</html>
```

### Step 1.6: Update Index Page

**File:** `apps/unicorn-store-spring/src/main/resources/templates/index.html`

Create a simple landing page:

```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<head>
    <meta charset="UTF-8">
    <title>Unicorn Store</title>
    <link rel="stylesheet" th:href="@{/webjars/bootstrap/css/bootstrap.min.css}">
</head>
<body>
    <div class="container mt-5">
        <h1>🦄 Unicorn Store</h1>
        <p class="lead">You can use <a href="/unicorns">REST API</a> and <a href="/webui">Web UI</a> to work with the application.</p>
    </div>
</body>
</html>
```

### Step 1.7: Add Index Controller

Update the existing `UnicornController.java` to redirect `/` to the index page, or create a simple `IndexController`:

**File:** `apps/unicorn-store-spring/src/main/java/com/unicorn/store/controller/IndexController.java`

```java
package com.unicorn.store.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class IndexController {

    @GetMapping("/")
    public String index() {
        return "index";
    }
}
```

**Note:** You'll need to remove or modify the existing `@GetMapping("/")` in `UnicornController.java` that returns a plain text response.

---

## Part 2: Harness Pipeline & Infrastructure Changes

### Step 2.1: Create New Harness Service

**File:** `.harness/services/unicorn_store_spring.yaml`

```yaml
service:
  name: unicorn-store-spring
  identifier: unicorn_store_spring
  orgIdentifier: sandbox
  projectIdentifier: soto_sandbox
  serviceDefinition:
    type: Kubernetes
    spec:
      manifests:
        - manifest:
            identifier: k8s_manifests
            type: K8sManifest
            spec:
              store:
                type: Github
                spec:
                  connectorRef: alexsotoharness
                  gitFetchType: Branch
                  paths:
                    - apps/unicorn-store-spring/k8s/templates/unicorn-store.yaml
                  repoName: java-on-aws
                  branch: main
              valuesPaths:
                - apps/unicorn-store-spring/k8s/values.yaml
              skipResourceVersioning: false
      artifacts:
        primary:
          primaryArtifactRef: <+input>
          sources:
            - identifier: dockerhub_image
              type: DockerRegistry
              spec:
                connectorRef: dockerhubalexsotoharness
                imagePath: alexsotoharness/unicorn-store-spring
                tag: <+input>
```

### Step 2.2: Create K8s Manifests Directory

Create the following directory structure:

```
apps/unicorn-store-spring/k8s/
├── templates/
│   └── unicorn-store.yaml
└── values.yaml
```

### Step 2.3: Create K8s Deployment Template

**File:** `apps/unicorn-store-spring/k8s/templates/unicorn-store.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{.Values.app.name}}
  labels:
    app: {{.Values.app.name}}
spec:
  replicas: {{.Values.app.replicas}}
  selector:
    matchLabels:
      app: {{.Values.app.name}}
  template:
    metadata:
      labels:
        app: {{.Values.app.name}}
    spec:
      initContainers:
        - name: wait-for-postgres
          image: busybox:1.36
          command: ['sh', '-c', 'until nc -z postgres {{.Values.database.port}}; do echo "Waiting for PostgreSQL..."; sleep 2; done; echo "PostgreSQL is ready!"']
      containers:
        - name: {{.Values.app.name}}
          image: {{.Values.image.repository}}:{{.Values.image.tag}}
          imagePullPolicy: {{.Values.image.pullPolicy}}
          ports:
            - containerPort: {{.Values.service.targetPort}}
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://{{.Values.database.host}}:{{.Values.database.port}}/{{.Values.database.name}}"
            - name: SPRING_DATASOURCE_USERNAME
              value: "{{.Values.database.username}}"
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{.Values.database.secretName}}
                  key: {{.Values.database.secretKey}}
          resources:
            requests:
              cpu: {{.Values.resources.requests.cpu}}
              memory: {{.Values.resources.requests.memory}}
            limits:
              cpu: {{.Values.resources.limits.cpu}}
              memory: {{.Values.resources.limits.memory}}
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: {{.Values.service.targetPort}}
            initialDelaySeconds: {{.Values.probes.initialDelaySeconds}}
            periodSeconds: {{.Values.probes.periodSeconds}}
            timeoutSeconds: {{.Values.probes.timeoutSeconds}}
            failureThreshold: {{.Values.probes.failureThreshold}}
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: {{.Values.service.targetPort}}
            initialDelaySeconds: {{.Values.probes.initialDelaySeconds}}
            periodSeconds: {{.Values.probes.periodSeconds}}
            timeoutSeconds: {{.Values.probes.timeoutSeconds}}
            failureThreshold: {{.Values.probes.failureThreshold}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{.Values.app.name}}
spec:
  type: {{.Values.service.type}}
  selector:
    app: {{.Values.app.name}}
  ports:
    - port: {{.Values.service.port}}
      targetPort: {{.Values.service.targetPort}}
```

### Step 2.4: Create K8s Values File

**File:** `apps/unicorn-store-spring/k8s/values.yaml`

```yaml
# Unicorn Store Spring - Helm/Go Template Values
# Used by Harness CD for Kubernetes deployment

# Application settings
app:
  name: unicorn-store-spring
  replicas: 1

# Container image settings
image:
  repository: alexsotoharness/unicorn-store-spring
  tag: latest
  pullPolicy: Always

# Service settings
service:
  type: NodePort
  port: 80
  targetPort: 8080

# Resource limits (Spring Boot needs less than WildFly)
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Health check settings (Spring Boot starts faster)
probes:
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

# Database settings (same as Jakarta version - reuses existing postgres)
database:
  host: postgres
  port: 5432
  name: unicorns
  username: postgres
  secretName: postgres-secret
  secretKey: POSTGRES_PASSWORD
```

### Step 2.5: Update Dockerfile for DockerHub Push

**File:** `apps/unicorn-store-spring/Dockerfile`

The existing Dockerfile should work. Ensure it builds correctly:

```dockerfile
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder

RUN yum install -y shadow-utils

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar
RUN rm -rf ~/.m2/repository

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "-Dserver.port=8080", "/store-spring.jar"]
```

---

## Part 3: Pipeline Modifications

### Step 3.1: Create New Pipeline or Modify Existing

You can either:
1. Create a new pipeline `Spring_Build_and_Deploy.yaml`
2. Modify the existing `Dayforce_Build_and_Deploy.yaml` to use the Spring service

**Key Changes for Pipeline:**

#### Build Stage Changes

```yaml
- step:
    type: Run
    name: Build JAR
    identifier: Build_JAR
    spec:
      connectorRef: account.harnessImage
      image: maven:3.9.9-amazoncorretto-21
      shell: Sh
      command: |
        cd apps/unicorn-store-spring
        mvn clean package -DskipTests -Dmaven.repo.local=/harness/.m2/repository
        ls -la target/

- step:
    type: BuildAndPushDockerRegistry
    name: Build and Push to DockerHub
    identifier: Build_and_Push_to_DockerHub
    spec:
      connectorRef: dockerhubalexsotoharness
      repo: alexsotoharness/unicorn-store-spring
      tags:
        - <+pipeline.sequenceId>
        - latest
      caching: true
      dockerfile: apps/unicorn-store-spring/Dockerfile
      context: apps/unicorn-store-spring
```

#### Deploy Stage Changes

Change the service reference:

```yaml
service:
  serviceRef: unicorn_store_spring  # Changed from unicorn_store_jakarta
  serviceInputs:
    serviceDefinition:
      type: Kubernetes
      spec:
        artifacts:
          primary:
            primaryArtifactRef: dockerhub_image
            sources:
              - identifier: dockerhub_image
                type: DockerRegistry
                spec:
                  tag: <+input>.default(latest)
```

---

## Part 4: Database Compatibility

### Step 4.1: Schema Compatibility

The Spring Boot app uses the **same `unicorns` table** as the Jakarta version:

| Field | Jakarta Entity | Spring Entity |
|-------|---------------|---------------|
| id | String | String |
| name | String | String |
| age | String | String |
| size | String | String |
| type | String | String |

**No schema changes required.** The existing DB DevOps changesets will work.

### Step 4.2: Reuse Existing Database Service

The `unicorn_store_database` service deploys:
- `postgres-secret` (Secret)
- `postgres-pvc` (PersistentVolumeClaim)
- `postgres` (Deployment)
- `postgres` (Service)

**No changes needed.** The Spring app connects to the same `postgres` service.

### Step 4.3: Environment Variables Mapping

| Jakarta (WildFly) | Spring Boot |
|-------------------|-------------|
| `DATASOURCE_JDBC_URL` | `SPRING_DATASOURCE_URL` |
| `DATASOURCE_USERNAME` | `SPRING_DATASOURCE_USERNAME` |
| `DATASOURCE_PASSWORD` | `SPRING_DATASOURCE_PASSWORD` |

The K8s template in Step 2.3 uses Spring's environment variable names.

---

## Part 5: Unit Tests for WebController

The Spring Boot app already has comprehensive tests using Testcontainers for the REST API. You'll need to add tests for the new `WebController`.

### Step 5.1: Create WebController Test

**File:** `apps/unicorn-store-spring/src/test/java/com/unicorn/store/integration/WebControllerTest.java`

```java
package com.unicorn.store.integration;

import com.unicorn.store.model.Unicorn;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestInfrastructure
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class WebControllerTest {

    @LocalServerPort
    private int port;

    private WebTestClient webTestClient;

    @BeforeEach
    void setUp() {
        webTestClient = WebTestClient.bindToServer()
            .baseUrl("http://localhost:" + port)
            .build();
    }

    @Test
    @Order(1)
    void shouldLoadWebUIPage() {
        webTestClient.get()
            .uri("/webui")
            .exchange()
            .expectStatus().isOk()
            .expectHeader().contentType(MediaType.TEXT_HTML);
    }

    @Test
    @Order(2)
    void shouldLoadIndexPage() {
        webTestClient.get()
            .uri("/")
            .exchange()
            .expectStatus().isOk()
            .expectHeader().contentType(MediaType.TEXT_HTML);
    }

    static String createdId;

    @Test
    @Order(3)
    void shouldCreateUnicornViaForm() {
        // First create via REST API to get an ID
        Unicorn unicorn = new Unicorn("WebTestUnicorn", "5", "Medium", "Rainbow");
        
        createdId = webTestClient.post()
            .uri("/unicorns")
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Unicorn.class)
            .returnResult()
            .getResponseBody()
            .getId();

        assertThat(createdId).isNotNull();
    }

    @Test
    @Order(4)
    void shouldLoadListFragment() {
        webTestClient.get()
            .uri("/webui/list")
            .exchange()
            .expectStatus().isOk()
            .expectBody(String.class)
            .value(html -> assertThat(html).contains("WebTestUnicorn"));
    }

    @Test
    @Order(5)
    void shouldLoadEditForm() {
        webTestClient.get()
            .uri("/webui/edit/" + createdId)
            .exchange()
            .expectStatus().isOk()
            .expectBody(String.class)
            .value(html -> {
                assertThat(html).contains("WebTestUnicorn");
                assertThat(html).contains("form");
            });
    }

    @Test
    @Order(6)
    void shouldDeleteViaWebUI() {
        webTestClient.delete()
            .uri("/webui/delete/" + createdId)
            .exchange()
            .expectStatus().isOk();

        // Verify deleted
        webTestClient.get()
            .uri("/unicorns/" + createdId)
            .exchange()
            .expectStatus().isNotFound();
    }
}
```

### Step 5.2: Run Tests Locally

```bash
cd apps/unicorn-store-spring

# Run all tests (uses Testcontainers for PostgreSQL)
mvn test

# Run only WebController tests
mvn test -Dtest=WebControllerTest

# Run with verbose output
mvn test -Dtest=WebControllerTest -X
```

### Step 5.3: Existing Tests (No Changes Needed)

The following tests already exist and will continue to work:

| Test Class | Purpose |
|------------|---------|
| `UnicornControllerTest` | REST API integration tests (CRUD) |
| `StoreApplicationTest` | Application context loads |
| `UnicornEqualsPropertyTest` | Property-based testing for equals/hashCode |
| `UnicornValidationPropertyTest` | Property-based testing for validation |
| `RequestContextPropertyTest` | Request context tests |

These tests use `@TestInfrastructure` annotation which automatically:
- Spins up PostgreSQL via Testcontainers
- Falls back to H2 if Testcontainers unavailable

---

## Part 6: Testing Checklist

### Local Testing

```bash
# 1. Build the application
cd apps/unicorn-store-spring
mvn clean package -DskipTests

# 2. Run locally with Docker Compose or direct
java -jar target/store-spring-1.0.0-exec.jar \
  --spring.datasource.url=jdbc:postgresql://localhost:5432/unicorns \
  --spring.datasource.username=postgres \
  --spring.datasource.password=postgres

# 3. Test endpoints
curl http://localhost:8080/              # Landing page
curl http://localhost:8080/webui         # Web UI
curl http://localhost:8080/unicorns      # REST API
curl http://localhost:8080/actuator/health
```

### Pipeline Testing

1. Push changes to Git
2. Run the pipeline
3. Verify:
   - [ ] Build stage completes
   - [ ] Docker image pushed to DockerHub
   - [ ] Database service deploys (postgres running)
   - [ ] Spring app deploys and reaches steady state
   - [ ] Web UI accessible at `/webui`
   - [ ] REST API accessible at `/unicorns`

---

## Summary of Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `apps/unicorn-store-spring/pom.xml` | Add Thymeleaf dependencies |
| `apps/unicorn-store-spring/src/main/java/.../WebController.java` | Web UI controller |
| `apps/unicorn-store-spring/src/main/java/.../IndexController.java` | Landing page controller |
| `apps/unicorn-store-spring/src/main/resources/templates/unicorns.html` | Main UI template |
| `apps/unicorn-store-spring/src/main/resources/templates/index.html` | Landing page |
| `apps/unicorn-store-spring/src/main/resources/templates/fragments/unicorn-table.html` | Table fragment |
| `apps/unicorn-store-spring/src/main/resources/templates/fragments/edit-form.html` | Edit form fragment |
| `apps/unicorn-store-spring/src/test/java/.../WebControllerTest.java` | Unit tests for Web UI |
| `apps/unicorn-store-spring/k8s/templates/unicorn-store.yaml` | K8s deployment |
| `apps/unicorn-store-spring/k8s/values.yaml` | K8s values |
| `.harness/services/unicorn_store_spring.yaml` | Harness service definition |

### Modified Files

| File | Change |
|------|--------|
| `apps/unicorn-store-spring/src/main/java/.../UnicornController.java` | Remove `@GetMapping("/")` |
| `.harness/pipelines/Dayforce_Build_and_Deploy.yaml` | Update to use Spring service (or create new pipeline) |

### Reused (No Changes)

| File | Notes |
|------|-------|
| `.harness/services/unicorn_store_database.yaml` | Same postgres deployment |
| `.harness/infrastructures/eksparsonunicorndev.yaml` | Same EKS dev infrastructure |
| `.harness/infrastructures/eksparsonunicornprod.yaml` | Same EKS prod infrastructure |
| `.harness/environments/awsnonprod.yaml` | Same environment |
| `.harness/environments/awsprod.yaml` | Same environment |
| `apps/unicorn-store-jakarta/k8s/templates/postgres.yaml` | Same postgres manifests |
| `apps/unicorn-store-jakarta/db/changelog.yaml` | Same DB DevOps changesets |
| `apps/unicorn-store-jakarta/db/changesets/*.yaml` | Same schema migrations |

---

## Estimated Effort

| Task | Time |
|------|------|
| Add Thymeleaf dependencies | 5 min |
| Create WebController | 15 min |
| Create HTML templates | 30 min |
| Create K8s manifests | 15 min |
| Create Harness service | 10 min |
| Update/create pipeline | 15 min |
| Testing & debugging | 30 min |
| **Total** | **~2 hours** |
