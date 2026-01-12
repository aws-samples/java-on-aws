# Unicorn Store - Local Kubernetes Deployment Guide

This guide walks you through building, containerizing, and deploying the **unicorn-store-spring** application to your local OrbStack Kubernetes cluster.

## Prerequisites

- [x] OrbStack with Kubernetes enabled
- [x] `kubectl` configured to use OrbStack
- [ ] Docker CLI (comes with OrbStack)
- [ ] DockerHub account (for pushing images)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    OrbStack Kubernetes                       │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   unicorn-store     │    │        PostgreSQL           │ │
│  │   (Spring Boot)     │───▶│        (Database)           │ │
│  │   Port: 8080        │    │        Port: 5432           │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
│            │                                                 │
│            ▼                                                 │
│  ┌─────────────────────┐                                    │
│  │   NodePort Service  │                                    │
│  │   localhost:30088   │                                    │
│  └─────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 1: Verify Your Environment

```bash
# Verify kubectl is pointing to OrbStack
kubectl config current-context
# Should show: orbstack

# Verify cluster is running
kubectl get nodes
# Should show: orbstack   Ready   control-plane,master   ...
```

---

## Step 2: Log in to DockerHub

```bash
# Log in to DockerHub (you'll be prompted for credentials)
docker login
```

---

## Step 3: Build the Container Image

Navigate to the application directory and build the image:

```bash
cd /Users/alexsoto/java-on-aws/apps/unicorn-store-spring

# Build the container image (multi-stage build, no local Java needed)
# Replace alexsotoharness with your actual DockerHub username
docker build -t alexsotoharness/unicorn-store-spring:latest .
```

> **Note**: The Dockerfile uses a multi-stage build with Maven and Amazon Corretto 25, so you don't need Java installed locally.

---

## Step 4: Push Image to DockerHub

```bash
# Push the image to DockerHub
docker push alexsotoharness/unicorn-store-spring:latest
```

---

## Step 5: Create Kubernetes Namespace

```bash
# Create a dedicated namespace for the application
kubectl create namespace unicorn-store
```

---

## Step 6: Deploy PostgreSQL

Create the PostgreSQL deployment and service:

```bash
# Apply PostgreSQL manifests
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: unicorn-store
type: Opaque
stringData:
  POSTGRES_USER: postgres
  POSTGRES_PASSWORD: postgres
  POSTGRES_DB: unicorns
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: unicorn-store
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: unicorn-store
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-secret
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: unicorn-store
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF
```

Wait for PostgreSQL to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=postgres -n unicorn-store --timeout=120s
```

---

## Step 7: Create the Database Schema

The application expects a `unicorns` table. Create it:

```bash
kubectl exec -it deploy/postgres -n unicorn-store -- psql -U postgres -d unicorns -c "
CREATE TABLE IF NOT EXISTS unicorns (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    age VARCHAR(255),
    size VARCHAR(255),
    type VARCHAR(255) NOT NULL
);"
```

---

## Step 8: Deploy the Unicorn Store Application

Create the application deployment and service:

```bash
# Replace alexsotoharness with your actual DockerHub username
kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store
  labels:
    app: unicorn-store-spring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unicorn-store-spring
  template:
    metadata:
      labels:
        app: unicorn-store-spring
    spec:
      containers:
        - name: unicorn-store-spring
          image: alexsotoharness/unicorn-store-spring:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://postgres:5432/unicorns"
            - name: SPRING_DATASOURCE_USERNAME
              value: "postgres"
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
            # Disable AWS SDK credential warnings for local deployment
            - name: AWS_REGION
              value: "us-east-1"
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 6
---
apiVersion: v1
kind: Service
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store
spec:
  type: NodePort
  selector:
    app: unicorn-store-spring
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30088
EOF
```

Wait for the application to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=unicorn-store-spring -n unicorn-store --timeout=180s
```

---

## Step 9: Verify the Deployment

Check all resources are running:

```bash
# Check pods
kubectl get pods -n unicorn-store

# Check services
kubectl get svc -n unicorn-store

# View application logs
kubectl logs -l app=unicorn-store-spring -n unicorn-store --tail=50
```

---

## Step 10: Access the Application

The application is now available at: **http://localhost:30088**

### Test the API:

```bash
# Health check
curl http://localhost:30088/actuator/health

# Welcome message
curl http://localhost:30088/

# List all unicorns (empty initially)
curl http://localhost:30088/unicorns

# Create a unicorn
curl -X POST http://localhost:30088/unicorns \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sparkle",
    "age": "5",
    "type": "Rainbow",
    "size": "Medium"
  }'

# List all unicorns (should show the created unicorn)
curl http://localhost:30088/unicorns
```

### Open in Browser:

- **Home**: http://localhost:30088/
- **Health**: http://localhost:30088/actuator/health
- **Metrics**: http://localhost:30088/actuator/prometheus

---

## Cleanup

To remove all resources when you're done:

```bash
# Delete the namespace (removes everything)
kubectl delete namespace unicorn-store
```

---

## Troubleshooting

### Application won't start

```bash
# Check pod status
kubectl describe pod -l app=unicorn-store-spring -n unicorn-store

# Check logs
kubectl logs -l app=unicorn-store-spring -n unicorn-store
```

### Database connection issues

```bash
# Verify PostgreSQL is running
kubectl get pods -l app=postgres -n unicorn-store

# Test database connectivity from within the cluster
kubectl run -it --rm debug --image=postgres:15-alpine -n unicorn-store -- \
  psql -h postgres -U postgres -d unicorns -c "SELECT 1"
```

### EventBridge warnings in logs

You may see warnings about EventBridge/AWS credentials - **this is expected** for local deployment. The application continues to work; events just won't be published to AWS.

---

## Quick Reference

| Resource | URL/Command |
|----------|-------------|
| Application | http://localhost:30088 |
| Health Check | http://localhost:30088/actuator/health |
| Metrics | http://localhost:30088/actuator/prometheus |
| Logs | `kubectl logs -l app=unicorn-store-spring -n unicorn-store -f` |
| Shell into app | `kubectl exec -it deploy/unicorn-store-spring -n unicorn-store -- sh` |
| Shell into DB | `kubectl exec -it deploy/postgres -n unicorn-store -- psql -U postgres -d unicorns` |

---

## What's Different from the AWS Workshop?

| AWS Workshop | Local Deployment |
|--------------|------------------|
| Amazon RDS PostgreSQL | PostgreSQL pod in K8s |
| Amazon ECR | DockerHub |
| Amazon EKS | OrbStack Kubernetes |
| AWS ALB Ingress | NodePort Service |
| EventBridge events | Disabled (logged only) |
| IAM Service Accounts | Not needed |

The core application functionality remains identical - you can create, read, update, and delete unicorns!
