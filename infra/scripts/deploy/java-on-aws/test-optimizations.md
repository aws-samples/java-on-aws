# 4-test-optimizations.sh

Build and test all Java container optimization methods for the Unicorn Store Spring application.

## Prerequisites

1. Run `1-containerize.sh` - creates ECR repo, builds baseline image with `:latest` tag
2. Run `2-eks.sh` - deploys to EKS with deployment using `:latest` image

## Usage

```bash
# Full benchmark: clean Docker, build all, deploy to EKS, measure startup, revert to :latest
./4-test-optimizations.sh --pre-clean --deploy --revert

# Build all images locally (no deploy)
./4-test-optimizations.sh

# Build single method locally
./4-test-optimizations.sh --only cds

# Build, push, and deploy single method
./4-test-optimizations.sh --only cds --deploy
```

## Options

| Option | Description |
|--------|-------------|
| (none) | Build all images locally, output results to stdout |
| `--deploy` | Push to ECR, deploy to EKS, measure startup times |
| `--only <method>` | Build only specified method (partial match: `cds`, `native`, etc.) |
| `--revert` | Revert deployment to `:latest` on exit (use with `--deploy`) |
| `--pre-clean` | Full Docker prune before building (removes all images, containers, volumes, build cache) |

## Methods

| Tag | Method | Build | Needs DB | Code Change | Notes |
|-----|--------|-------|----------|-------------|-------|
| 01-multi-stage | Baseline with 1 CPU | Yes | No | No | Baseline build + deploy |
| 01-multi-stage-2cpu | Baseline with 2 CPUs | No | No | No | Deploy variant, same image |
| 01-multi-stage-pod-resize | In-place pod resize | No | No | No | Deploy variant, CPU boost controller |
| 02-jib | Google Jib Maven plugin | Yes | No | No | No Dockerfile |
| 03-custom-jre | Custom JRE with jlink | Yes | No | No | Smaller image |
| 04-soci | Seekable OCI (lazy loading) | Yes | No | No | SOCI index after push |
| 05-cds | Class Data Sharing | Yes | Yes | No | Paketo Buildpacks |
| 06-aot | Ahead-of-Time compilation | Yes | Yes | No | Java 25+ AOT cache |
| 07-native | GraalVM Native Image | Yes | No | No | Long build time |
| 08-crac | Coordinated Restore at Checkpoint | Yes | Yes | Yes | UnicornPublisher swap |

## Flow

### Build-only mode (default)

```
For each method:
  1. Skip build if deploy variant (01-multi-stage-2cpu, 01-multi-stage-pod-resize)
  2. Pre-build hooks (CRaC: swap UnicornPublisher.crac)
  3. Start PostgreSQL if needed (CDS, AOT, CRaC) - AWS RDS or local Docker
  4. Build image (docker build, mvn jib:dockerBuild, or pack build)
  5. Stop PostgreSQL
  6. Post-build hooks (CRaC: restore UnicornPublisher.java)
  7. Output: Method | ✅/❌ | Size | Time
```

### Deploy mode (`--deploy`)

```
┌─────────────────────────────────────────────────────────────────┐
│  MAIN PROCESS (build)              BACKGROUND WATCHER (deploy)  │
├─────────────────────────────────────────────────────────────────┤
│  Start watcher ──────────────────► Initialize results file      │
│                                                                 │
│  For each method:                                               │
│    Build image (skip for variants)                              │
│    Push to ECR (skip for variants)                              │
│    Write to queue ───────────────► Read queue                   │
│    Continue immediately                                         │
│                                    Handle deploy variants:      │
│                                      01-multi-stage: set 1 CPU  │
│                                      01-multi-stage-2cpu: 2 CPU │
│                                      01-multi-stage-pod-resize: │
│                                        install CPU boost ctrl   │
│                                    Or: kubectl set image :tag   │
│                                    Wait for rollout             │
│                                    Record startup time          │
│                                    Cleanup (pod-resize)         │
│                                    Write to results file        │
│                                                                 │
│  Write END marker ───────────────► Exit                         │
│  Wait for watcher                                               │
│  Print final results                                            │
└─────────────────────────────────────────────────────────────────┘
```

## Output Files (deploy mode)

All output goes to `/tmp/test-optimizations/` (or `${SCRIPT_DIR}/.test-optimizations/` if /tmp not writable):

| File | Description |
|------|-------------|
| `queue.txt` | Build→Deploy queue (status\|tag\|size_local\|size_ecr\|build_time\|error) |
| `results.txt` | Final results table |
| `watcher.pid` | Background watcher PID (temporary) |
| `<tag>-build.txt` | Build and push logs per image |
| `<tag>-deploy.txt` | Deploy logs per image |

## Results Format

### Build-only stdout
```
Method                    | Build | Size Local | Time
--------------------------|-------|------------|------
01-multi-stage            | ✅    | 598MB      | 45s
01-multi-stage-2cpu       | ✅    | N/A        | 0s
01-multi-stage-pod-resize | ✅    | N/A        | 0s
02-jib                    | ✅    | 590MB      | 30s
05-cds                    | ✅    | 1.23GB     | 2m23s
07-native                 | ❌    | N/A        | 5m30s
```

### Deploy mode results file
```
Method                    | Size Local | Size ECR | Build Time | Startup Time
--------------------------|------------|----------|------------|-------------
01-multi-stage            | 598MB      | 580MB    | 45s        | 10.234 seconds
01-multi-stage-2cpu       | N/A        | N/A      | 0s         | 6.123 seconds
01-multi-stage-pod-resize | N/A        | N/A      | 0s         | 5.987 seconds
02-jib                    | 590MB      | 570MB    | 30s        | 10.100 seconds
05-cds                    | 1.23GB     | 578MB    | 2m23s      | 3.916 seconds
06-aot                    | 1.34GB     | 428MB    | 56s        | 4.0 seconds
08-crac                   | 1.1GB      | 1.0GB    | 3m20s      | 0.087 seconds
```

## Database Configuration

The script automatically detects database configuration:

1. **AWS RDS** (preferred): Tries to get credentials from SSM Parameter Store and Secrets Manager
   - `workshop-db-connection-string` - JDBC URL
   - `workshop-db-secret` - username/password

2. **Local Docker** (fallback): Starts PostgreSQL container if AWS credentials not available
   - Uses `host.docker.internal:5432` for Docker build access

## Special Build Methods

### CDS (05-cds)
Uses Paketo Buildpacks instead of Dockerfile:
- Installs `pack` CLI if not available
- `BP_JVM_CDS_ENABLED=true` - creates CDS archive during build
- `BPL_JVM_CDS_ENABLED=true` - uses CDS archive at runtime

### Pod Resize (01-multi-stage-pod-resize)
Installs Kube Startup CPU Boost controller:
- Creates `StartupCPUBoost` resource with 100% CPU increase
- Automatically removes boost when pod becomes ready
- Cleans up controller after test

## Environment

Requires workshop environment (`/etc/profile.d/workshop.sh`) with:
- `ACCOUNT_ID` - AWS account ID
- `AWS_REGION` - AWS region

Database credentials are fetched automatically from AWS or use local Docker fallback.

## Notes

- Deploy variants (01-multi-stage-2cpu, 01-multi-stage-pod-resize) use the same 01-multi-stage image
- CDS uses Paketo Buildpacks (not Dockerfile) for proper CDS archive creation
- Native image may fail on ARM (macOS) - works on x86-64 Linux
- CRaC requires x86-64 for `-XX:CPUFeatures=generic`
- SOCI requires `soci` CLI tool installed
- Pod resize requires EKS 1.27+ with in-place pod resize support
