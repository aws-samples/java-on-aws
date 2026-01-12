# Unicorn Store Jakarta/WildFly - Local Kubernetes Deployment Guide

This guide walks you through building, containerizing, and deploying the **unicorn-store-jakarta** (WildFly) application to your local OrbStack Kubernetes cluster. This version includes a web UI.

## Prerequisites

- [x] OrbStack with Kubernetes enabled
- [x] `kubectl` configured to use OrbStack
- [ ] Docker CLI (comes with OrbStack)
- [ ] DockerHub account (for pushing images)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    OrbStack Kubernetes                       │
│              Namespace: unicorn-store-jakarta                │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   unicorn-store     │    │        PostgreSQL           │ │
│  │   (WildFly + UI)    │───▶│        (Database)           │ │
│  │   Port: 8080        │    │        Port: 5432           │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
│            │                                                 │
│            ▼                                                 │
│  ┌─────────────────────┐                                    │
│  │   NodePort Service  │                                    │
│  │   localhost:30089   │                                    │
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
cd /Users/alexsoto/java-on-aws/apps/unicorn-store-jakarta

# Build the container image using the WildFly Dockerfile
docker build -f wildfly/Dockerfile -t alexsotoharness/unicorn-store-jakarta:latest .
```

> **Note**: The Dockerfile uses a multi-stage build with Maven and Amazon Corretto 21, so you don't need Java installed locally. The WildFly image includes automatic PostgreSQL datasource configuration.

---

## Step 4: Push Image to DockerHub

```bash
# Push the image to DockerHub
docker push alexsotoharness/unicorn-store-jakarta:latest
```

---

## Step 5: Create Kubernetes Namespace

```bash
# Create a dedicated namespace for the Jakarta application
kubectl create namespace unicorn-store-jakarta
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
  namespace: unicorn-store-jakarta
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
  namespace: unicorn-store-jakarta
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
  namespace: unicorn-store-jakarta
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
  namespace: unicorn-store-jakarta
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
kubectl wait --for=condition=ready pod -l app=postgres -n unicorn-store-jakarta --timeout=120s
```

---

## Step 7: Deploy the Unicorn Store Jakarta Application

Create the application deployment and service:

```bash
kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-store-jakarta
  namespace: unicorn-store-jakarta
  labels:
    app: unicorn-store-jakarta
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unicorn-store-jakarta
  template:
    metadata:
      labels:
        app: unicorn-store-jakarta
    spec:
      containers:
        - name: unicorn-store-jakarta
          image: alexsotoharness/unicorn-store-jakarta:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          env:
            - name: DATASOURCE_JDBC_URL
              value: "jdbc:postgresql://postgres:5432/unicorns"
            - name: DATASOURCE_USERNAME
              value: "postgres"
            - name: DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 6
---
apiVersion: v1
kind: Service
metadata:
  name: unicorn-store-jakarta
  namespace: unicorn-store-jakarta
spec:
  type: NodePort
  selector:
    app: unicorn-store-jakarta
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30089
EOF
```

Wait for the application to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=unicorn-store-jakarta -n unicorn-store-jakarta --timeout=180s
```

---

## Step 8: Verify the Deployment

Check all resources are running:

```bash
# Check pods
kubectl get pods -n unicorn-store-jakarta

# Check services
kubectl get svc -n unicorn-store-jakarta

# View application logs
kubectl logs -l app=unicorn-store-jakarta -n unicorn-store-jakarta --tail=50
```

---

## Step 9: Access the Application

The application is now available at: **http://localhost:30089**

### Web UI:

Open your browser and navigate to:

- **Unicorn Management UI**: http://localhost:30089/webui/unicorns.xhtml

The UI provides:
- Data table showing all unicorns
- Add new unicorn (+ button)
- Edit unicorn (pencil icon)
- Delete unicorn (trash icon)

### REST API (also available):

```bash
# List all unicorns
curl http://localhost:30089/api/unicorns

# Create a unicorn
curl -X POST http://localhost:30089/api/unicorns \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sparkle",
    "age": "5",
    "type": "Rainbow",
    "size": "Medium"
  }'
```

---

## Cleanup

To remove all resources when you're done:

```bash
# Delete the namespace (removes everything)
kubectl delete namespace unicorn-store-jakarta
```

---

## Troubleshooting

### Application won't start

```bash
# Check pod status
kubectl describe pod -l app=unicorn-store-jakarta -n unicorn-store-jakarta

# Check logs
kubectl logs -l app=unicorn-store-jakarta -n unicorn-store-jakarta
```

### Database connection issues

```bash
# Verify PostgreSQL is running
kubectl get pods -l app=postgres -n unicorn-store-jakarta

# Test database connectivity from within the cluster
kubectl run -it --rm debug --image=postgres:15-alpine -n unicorn-store-jakarta -- \
  psql -h postgres -U postgres -d unicorns -c "SELECT 1"
```

### UI not loading

Make sure you're accessing the correct path: `/webui/unicorns.xhtml` (not just `/`)

---

## Quick Reference

| Resource | URL/Command |
|----------|-------------|
| **Home** | http://localhost:30089/ |
| **Web UI** | http://localhost:30089/webui/unicorns.xhtml |
| **REST API** | http://localhost:30089/api/unicorns |
| **Logs** | `kubectl logs -l app=unicorn-store-jakarta -n unicorn-store-jakarta -f` |
| **Shell into app** | `kubectl exec -it deploy/unicorn-store-jakarta -n unicorn-store-jakarta -- sh` |
| **Shell into DB** | `kubectl exec -it deploy/postgres -n unicorn-store-jakarta -- psql -U postgres -d unicorns` |

---

## Comparison: Spring vs Jakarta/WildFly

| Feature | Spring Version | Jakarta/WildFly Version |
|---------|---------------|------------------------|
| Namespace | `unicorn-store` | `unicorn-store-jakarta` |
| Port | 30088 | 30089 |
| Framework | Spring Boot 4 | WildFly 37 |
| Java Version | 25 | 21 |
| Has Web UI | ❌ No (API only) | ✅ Yes (PrimeFaces) |
| REST API Path | `/unicorns` | `/api/unicorns` |
| Config Prefix | `SPRING_DATASOURCE_*` | `DATASOURCE_*` |
