# Harness Database DevOps Implementation Plan

This document outlines the step-by-step plan to integrate Harness DB DevOps into the Unicorn Store Jakarta pipeline for managing PostgreSQL schema changes.

## Overview

| Item | Value |
|------|-------|
| **Target Environment** | EKS Dev |
| **Database** | PostgreSQL (already deployed to EKS Dev cluster) |
| **Current Schema Management** | Hibernate auto-DDL (`update`) |
| **Goal** | Version-controlled schema migrations via Harness DB DevOps |

---

## Prerequisites Checklist

- [x] Harness DB DevOps feature flag (`DBOPS_ENABLED`) enabled
- [x] Delegate can reach PostgreSQL in EKS Dev cluster
- [x] PostgreSQL instance running in EKS Dev
- [ ] JDBC Connector created in Harness
- [ ] DB Instance registered in Harness
- [ ] DB Schema registered in Harness

---

## Implementation Steps

### Step 1: Create JDBC Connector in Harness UI

Create a JDBC connector to allow Harness to connect to your PostgreSQL database.

**Navigate to:** Project Settings → Connectors → New Connector → JDBC

| Field | Value |
|-------|-------|
| **Name** | `postgres-eks-dev` |
| **Identifier** | `postgres_eks_dev` |
| **JDBC URL** | `jdbc:postgresql://postgres.unicorn-dev:5432/unicorns?sslmode=disable` |
| **Username** | `postgres` |
| **Password** | `postgres` (or create a Harness Secret for better security) |
| **Delegate Selector** | Select the delegate that has network access to EKS Dev |

> **Note:** The service name is `postgres`, namespace is `unicorn-dev`, database is `unicorns`.

**Verification:** Test the connection before saving.

---

### Step 2: Create Changelog Files in Repository

**⚠️ IMPORTANT:** The changelog file must exist in the repo before you can register the schema in Harness.

Create the following files:

#### 2.1 Main Changelog File

**File:** `apps/unicorn-store-jakarta/db/changelog.yaml`

```yaml
databaseChangeLog:
  - include:
      file: changesets/001-initial-schema.yaml
      relativeToChangelogFile: true
```

#### 2.2 Initial Schema Changeset

**File:** `apps/unicorn-store-jakarta/db/changesets/001-initial-schema.yaml`

```yaml
databaseChangeLog:
  - changeSet:
      id: 001-create-unicorns-table
      author: unicorn-store-team
      labels: initial-schema
      comment: Create initial unicorns table (baseline from Hibernate auto-DDL)
      preConditions:
        - onFail: MARK_RAN
        - not:
            tableExists:
              tableName: unicorns
      changes:
        - createTable:
            tableName: unicorns
            columns:
              - column:
                  name: id
                  type: VARCHAR(255)
                  constraints:
                    primaryKey: true
                    nullable: false
              - column:
                  name: name
                  type: VARCHAR(255)
              - column:
                  name: age
                  type: VARCHAR(255)
              - column:
                  name: size
                  type: VARCHAR(255)
              - column:
                  name: type
                  type: VARCHAR(255)
      rollback:
        - dropTable:
            tableName: unicorns
```

**After creating files:** `git add . && git commit -m "Add DB DevOps changelog" && git push`

---

### Step 3: Register Database Schema in Harness

**Navigate to:** Database DevOps → **DB Schemas** → **+ New DB Schema**

| Field | Value |
|-------|-------|
| **Name** | `unicorn-store-schema` |
| **Migration Type** | `Liquibase` |
| **Connection Type** | `Connector` |
| **Connector** | `gh-alexsoto-harness` (your GitHub connector) |
| **Repository** | `java-on-aws` |
| **Path to Schema File** | `apps/unicorn-store-jakarta/db/changelog.yaml` |
| **Associated Service** | `unicorn_store_database` (optional) |

---

### Step 4: Create Database Instance in Harness

Create the instance that links the schema to the actual database connection.

**Navigate to:** Database DevOps → **DB Instances** → **+ New DB Instance**

| Field | Value |
|-------|-------|
| **Name** | `unicorn-store-postgres-dev` |
| **Tags** | (leave empty) |
| **Select Branch** | `main` |
| **Connector** | `postgres-eks-dev` (from Step 1) |
| **Context** | (leave empty - used for Liquibase contexts) |
| **Substitute Properties** | (leave empty - used for changelog placeholders) |

---

### Step 5: Add DB DevOps Stage to Pipeline

Add a new stage to the pipeline that runs schema migrations before the application deployment.

**File:** `.harness/pipelines/Dayforce_Build_and_Deploy.yaml`

Add this stage **before** the EKS Dev Deploy stage:

```yaml
- stage:
    name: Database DevOps
    identifier: Database_DevOps
    description: Apply database schema changes
    type: Custom
    spec:
      execution:
        steps:
          - stepGroup:
              name: Deploy DB Changes
              identifier: Deploy_DB_Changes
              steps:
                - step:
                    type: DBSchemaApply
                    name: Apply Schema
                    identifier: Apply_Schema
                    spec:
                      connectorRef: account.harnessImage
                      migrationType: Liquibase
                      dbSchema: unicornstoreschema
                      dbInstance: unicornstorepostgresdev
                    timeout: 10m
              stepGroupInfra:
                type: KubernetesDirect
                spec:
                  connectorRef: eksparson
                  namespace: unicorn-dev
        rollbackSteps: []
      serviceDependencies: []
    tags: {}
```

---

### Step 6: Update Hibernate Configuration

Change Hibernate from auto-DDL to validation-only mode.

**File:** `apps/unicorn-store-jakarta/src/main/webapp/WEB-INF/classes/META-INF/persistence.xml`

**Before:**
```xml
<property name="hibernate.hbm2ddl.auto" value="update" />
```

**After:**
```xml
<property name="hibernate.hbm2ddl.auto" value="validate" />
```

> **Note:** `validate` ensures Hibernate checks that entities match the schema but doesn't modify it. This catches mismatches early.

---

## Workflow for Future Schema Changes

Once set up, follow this workflow for any database changes:

### Adding a New Column Example

1. **Create a new changeset file:**

   **File:** `apps/unicorn-store-jakarta/db/changesets/002-add-color-column.yaml`

   ```yaml
   databaseChangeLog:
     - changeSet:
         id: 002-add-color-column
         author: your-name
         labels: feature-unicorn-colors
         comment: Add color column to unicorns table
         changes:
           - addColumn:
               tableName: unicorns
               columns:
                 - column:
                     name: color
                     type: VARCHAR(50)
                     defaultValue: "rainbow"
         rollback:
           - dropColumn:
               tableName: unicorns
               columnName: color
   ```

2. **Update main changelog:**

   **File:** `apps/unicorn-store-jakarta/db/changelog.yaml`

   ```yaml
   databaseChangeLog:
     - include:
         file: changesets/001-initial-schema.yaml
         relativeToChangelogFile: true
     - include:
         file: changesets/002-add-color-column.yaml
         relativeToChangelogFile: true
   ```

3. **Update Java entity:**

   ```java
   @Entity(name = "unicorns")
   public class Unicorn {
       // ... existing fields
       private String color;
       // ... getter/setter
   }
   ```

4. **Commit and push** - Pipeline will automatically apply the migration.

---

## Verification Checklist

After implementation, verify:

- [ ] JDBC connector test connection succeeds
- [ ] DB Instance shows as connected in Harness UI
- [ ] DB Schema is registered and shows changelog path
- [ ] Pipeline runs successfully with DB Migration stage
- [ ] Schema changes are tracked in `DATABASECHANGELOG` table
- [ ] Hibernate validation passes (no schema mismatch errors)

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| JDBC connection fails | Verify delegate can reach PostgreSQL service, check credentials |
| Changeset already ran | Check `DATABASECHANGELOG` table, use `preConditions` to handle |
| Rollback fails | Ensure rollback section is defined in changeset |
| Hibernate validation error | Entity doesn't match schema - check column types/names |

### Useful Commands

```bash
# Connect to PostgreSQL and check changelog tracking table
kubectl exec -it deploy/postgres -n unicorn-store-jakarta -- \
  psql -U postgres -d unicorns -c "SELECT * FROM databasechangelog;"

# Check if unicorns table exists
kubectl exec -it deploy/postgres -n unicorn-store-jakarta -- \
  psql -U postgres -d unicorns -c "\d unicorns"
```

---

## Progress Tracking

| Step | Status | Notes |
|------|--------|-------|
| 1. Create JDBC Connector | ⬜ Pending | Do in Harness UI |
| 2. Register DB Instance | ⬜ Pending | Do in Harness UI |
| 3. Register DB Schema | ⬜ Pending | Do in Harness UI |
| 4. Create Changelog Files | ⬜ Pending | Create in repo |
| 5. Add Pipeline Stage | ⬜ Pending | Update pipeline YAML |
| 6. Update Hibernate Config | ⬜ Pending | Change to validate |
| 7. Test Pipeline | ⬜ Pending | Run and verify |

---

## Next Steps

1. **Start with Step 1** - Create the JDBC connector in Harness UI
2. Let me know when ready, and I'll create the changelog files (Step 4)
3. Then we'll update the pipeline YAML (Step 5)
