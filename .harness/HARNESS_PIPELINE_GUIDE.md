# Unicorn Store Jakarta - Harness CI/CD Pipeline Guide

This guide documents the Harness pipeline setup for building and deploying the **unicorn-store-jakarta** application to a local OrbStack Kubernetes cluster.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Pipeline Structure](#pipeline-structure)
- [Harness Resources](#harness-resources)
- [Kubernetes Manifests](#kubernetes-manifests)
- [Running the Pipeline](#running-the-pipeline)
- [Future Enhancements](#future-enhancements)
- [Troubleshooting](#troubleshooting)

---

## Overview

The **Dayforce Build and Deploy** pipeline provides a complete CI/CD workflow for the unicorn-store-jakarta application:

| Stage | Description |
|-------|-------------|
| **Build** | Runs tests with Test Intelligence, builds WAR, pushes Docker image |
| **Deploy to OrbStack** | Deploys to local Kubernetes cluster using rolling deployment |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Harness Pipeline                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      CI Stage (Build)                            │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │   │
│  │  │ Run Tests    │─▶│ Build WAR    │─▶│ Build & Push Docker    │ │   │
│  │  │ (Test Intel) │  │ (Maven)      │  │ (sequenceId + latest)  │ │   │
│  │  └──────────────┘  └──────────────┘  └────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                   CD Stage (Deploy to OrbStack)                  │   │
│  │  ┌──────────────────────────────────────────────────────────┐   │   │
│  │  │              K8s Rolling Deployment                       │   │   │
│  │  │  • Service: unicorn_store_jakarta                         │   │   │
│  │  │  • Environment: harnessdevenv                             │   │   │
│  │  │  • Infrastructure: orbstack_local                         │   │   │
│  │  └──────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    OrbStack Kubernetes Cluster                           │
│                   Namespace: unicorn-store-jakarta                       │
│  ┌─────────────────────────┐    ┌─────────────────────────────────────┐ │
│  │   unicorn-store-jakarta │    │           PostgreSQL                 │ │
│  │   (WildFly + UI)        │───▶│           (Database)                 │ │
│  │   Port: 8080            │    │           Port: 5432                 │ │
│  └─────────────────────────┘    └─────────────────────────────────────┘ │
│            │                                                             │
│            ▼                                                             │
│  ┌─────────────────────────┐                                            │
│  │   NodePort Service      │                                            │
│  │   localhost:30089       │                                            │
│  └─────────────────────────┘                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Harness Setup

| Resource | Identifier | Description |
|----------|------------|-------------|
| **Organization** | `sandbox` | Harness organization |
| **Project** | `soto_sandbox` | Harness project |
| **GitHub Connector** | `alexsotoharness` | GitHub account connector |
| **DockerHub Connector** | `dockerhubalexsotoharness` | DockerHub registry connector |
| **K8s Connector** | `harnessk8sconnector` | OrbStack K8s connector (uses `soto-local` delegate) |
| **Environment** | `harnessdevenv` | Pre-production environment |

### Local Environment

- OrbStack with Kubernetes enabled
- `kubectl` configured to use OrbStack
- Harness delegate (`soto-local`) running in the cluster

Verify your setup:

```bash
# Check kubectl context
kubectl config current-context
# Should show: orbstack

# Check delegate is running
kubectl get pods -n harness-delegate-ng
```

---

## Pipeline Structure

### File: `.harness/pipelines/Dayforce_Build_and_Deploy.yaml`

#### Stage 1: Build (CI)

| Step | Type | Description |
|------|------|-------------|
| **Run Tests with TI** | `RunTests` | Runs Maven tests with Test Intelligence enabled |
| **Build WAR** | `Run` | Builds the WAR file using Maven |
| **Build and Push to DockerHub** | `BuildAndPushDockerRegistry` | Builds Docker image and pushes with tags |

**Test Intelligence**: Automatically selects only the tests affected by code changes, reducing build time.

**Docker Tags**:
- `<+pipeline.sequenceId>` - Unique build number for traceability
- `latest` - Always points to the most recent build

#### Stage 2: Deploy to OrbStack (CD)

| Step | Type | Description |
|------|------|-------------|
| **Rolling Deployment** | `K8sRollingDeploy` | Deploys using Kubernetes rolling update strategy |
| **Rollback** | `K8sRollingRollback` | Automatic rollback on failure |

---

## Harness Resources

### Service Definition

**File**: `.harness/services/unicorn_store_jakarta.yaml`

```yaml
service:
  name: unicorn-store-jakarta
  identifier: unicorn_store_jakarta
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
                  paths:
                    - apps/unicorn-store-jakarta/k8s/templates
                  repoName: java-on-aws
                  branch: main
              valuesPaths:
                - apps/unicorn-store-jakarta/k8s/values.yaml
      artifacts:
        primary:
          sources:
            - identifier: dockerhub_image
              type: DockerRegistry
              spec:
                connectorRef: dockerhubalexsotoharness
                imagePath: alexsotoharness/unicorn-store-jakarta
```

### Infrastructure Definition

**File**: `.harness/infrastructures/orbstack_local.yaml`

```yaml
infrastructureDefinition:
  name: orbstack-local
  identifier: orbstack_local
  environmentRef: harnessdevenv
  deploymentType: Kubernetes
  type: KubernetesDirect
  spec:
    connectorRef: harnessk8sconnector
    namespace: unicorn-store-jakarta
    releaseName: release-<+INFRA_KEY_SHORT_ID>
```

---

## Kubernetes Manifests

All manifests use **Go templates** for flexibility.

### Directory Structure

```
apps/unicorn-store-jakarta/k8s/
├── values.yaml                    # Configuration values
└── templates/
    ├── namespace.yaml             # Namespace definition
    ├── postgres-secret.yaml       # Database credentials
    ├── postgres-pvc.yaml          # Persistent volume claim
    ├── postgres-deployment.yaml   # PostgreSQL deployment
    ├── postgres-service.yaml      # PostgreSQL service
    ├── deployment.yaml            # Application deployment
    └── service.yaml               # Application service (NodePort)
```

### Key Configuration (values.yaml)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `app.name` | `unicorn-store-jakarta` | Application name |
| `app.namespace` | `unicorn-store-jakarta` | Kubernetes namespace |
| `app.replicas` | `1` | Number of replicas |
| `image.repository` | `alexsotoharness/unicorn-store-jakarta` | Docker image |
| `image.tag` | `latest` | Image tag (overridden by pipeline) |
| `service.nodePort` | `30089` | External access port |
| `database.host` | `postgres` | PostgreSQL service name |
| `database.name` | `unicorns` | Database name |

---

## Running the Pipeline

### From Harness UI

1. Navigate to **Pipelines** → **Dayforce Build and Deploy**
2. Click **Run**
3. Select the branch to build
4. Click **Run Pipeline**

### Accessing the Application

After successful deployment:

| Resource | URL |
|----------|-----|
| **Home** | http://localhost:30089/ |
| **Web UI** | http://localhost:30089/webui/unicorns.xhtml |
| **REST API** | http://localhost:30089/api/unicorns |

---

## Future Enhancements

### 1. DB DevOps Stage (Liquibase/Flyway)

Currently, the database schema is managed by Hibernate auto-DDL (`hibernate.hbm2ddl.auto=update`). To add controlled database migrations:

1. Create a JDBC connector for PostgreSQL
2. Add Liquibase/Flyway migration files
3. Add a DB DevOps stage between Build and Deploy

```yaml
- stage:
    name: Database Migration
    identifier: Database_Migration
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: DbDevOps
              name: Run Migrations
              spec:
                connectorRef: postgres_jdbc_connector
                # ... migration config
```

### 2. Security Scanning

Add SAST/SCA scanning to the CI stage:

```yaml
- step:
    type: Security
    name: Security Scan
    spec:
      privileged: true
      settings:
        product_name: semgrep
        scan_type: repository
```

### 3. Multi-Environment Deployment

Extend the pipeline with additional environments:

- **Dev** → OrbStack (current)
- **Staging** → Cloud K8s cluster
- **Production** → Production K8s cluster with approval gates

### 4. GitOps Integration

Convert to GitOps workflow using Harness GitOps with ArgoCD.

---

## Troubleshooting

### Pipeline Fails at Test Stage

```bash
# Check if tests pass locally
cd apps/unicorn-store-jakarta
mvn clean test
```

### Docker Build Fails

```bash
# Test Docker build locally
cd apps/unicorn-store-jakarta
docker build -f wildfly/Dockerfile -t test:local .
```

### Deployment Fails

```bash
# Check pod status
kubectl get pods -n unicorn-store-jakarta

# Check pod logs
kubectl logs -l app=unicorn-store-jakarta -n unicorn-store-jakarta

# Describe pod for events
kubectl describe pod -l app=unicorn-store-jakarta -n unicorn-store-jakarta
```

### Database Connection Issues

```bash
# Verify PostgreSQL is running
kubectl get pods -l app=postgres -n unicorn-store-jakarta

# Test database connectivity
kubectl run -it --rm debug --image=postgres:15-alpine -n unicorn-store-jakarta -- \
  psql -h postgres -U postgres -d unicorns -c "SELECT 1"
```

### Delegate Not Connected

```bash
# Check delegate status
kubectl get pods -n harness-delegate-ng

# Check delegate logs
kubectl logs -l app.kubernetes.io/name=harness-delegate-ng -n harness-delegate-ng
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `kubectl get pods -n unicorn-store-jakarta` | List all pods |
| `kubectl logs -f deploy/unicorn-store-jakarta -n unicorn-store-jakarta` | Stream app logs |
| `kubectl exec -it deploy/postgres -n unicorn-store-jakarta -- psql -U postgres -d unicorns` | Connect to DB |
| `kubectl delete namespace unicorn-store-jakarta` | Clean up everything |

---

## Files Created

| File | Purpose |
|------|---------|
| `.harness/pipelines/Dayforce_Build_and_Deploy.yaml` | Main pipeline definition |
| `.harness/services/unicorn_store_jakarta.yaml` | Service definition |
| `.harness/infrastructures/orbstack_local.yaml` | Infrastructure definition |
| `apps/unicorn-store-jakarta/k8s/values.yaml` | Helm/Go template values |
| `apps/unicorn-store-jakarta/k8s/templates/*.yaml` | Kubernetes manifests |
