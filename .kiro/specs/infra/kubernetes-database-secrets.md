# Kubernetes Database Secrets

This document describes how to use database secrets from AWS Secrets Manager in Kubernetes pods.

## Overview

The workshop infrastructure automatically creates a SecretProviderClass that syncs database credentials from AWS Secrets Manager to Kubernetes secrets.

## Available Secrets

| Kubernetes Secret Key | Description |
|----------------------|-------------|
| `DB_USERNAME` | Database username |
| `DB_PASSWORD` | Database password |
| `DB_CONNECTION_STRING` | Full JDBC URL |

## Usage

### Using secrets as environment variables:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: SPRING_DATASOURCE_URL
      valueFrom:
        secretKeyRef:
          name: workshop-db-secret
          key: DB_CONNECTION_STRING
    - name: SPRING_DATASOURCE_USERNAME
      valueFrom:
        secretKeyRef:
          name: workshop-db-secret
          key: DB_USERNAME
    - name: SPRING_DATASOURCE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: workshop-db-secret
          key: DB_PASSWORD
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "workshop-db-secrets"
```

### Using all secrets at once:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    envFrom:
    - secretRef:
        name: workshop-db-secret
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "workshop-db-secrets"
```

## Verification

```bash
# Check if secret exists
kubectl get secret workshop-db-secret

# View secret keys
kubectl describe secret workshop-db-secret
```