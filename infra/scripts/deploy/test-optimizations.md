# test-optimizations.sh

Build and test all Java container optimization methods for the Unicorn Store Spring application.

## Prerequisites

1. Run `containerize.sh` - creates ECR repo, builds baseline image with `:latest` and `:02-multi-stage` tags
2. Run `eks.sh` - deploys to EKS with deployment using `:latest` image

## Usage

```bash
./test-optimizations.sh              # Build all images locally
./test-optimizations.sh --deploy     # Build, push to ECR, deploy to EKS, measure startup
./test-optimizations.sh --only cds   # Build single method
./test-optimizations.sh --only cds --deploy
```

## Options

| Option | Description |
|--------|-------------|
| (none) | Build all images locally, output results to stdout |
| `--deploy` | Push to ECR, deploy to EKS, measure startup/restart times |
| `--only <method>` | Build only specified method (partial match: `cds`, `native`, etc.) |

## Methods

| Tag | Method | Needs DB | Code Change | Special |
|-----|--------|----------|-------------|---------|
| 02-multi-stage | Optimized Dockerfile | No | No | Baseline |
| 03-jib | Google Jib Maven plugin | No | No | No Dockerfile |
| 04-custom-jre | Custom JRE with jlink | No | No | |
| 05-soci | Seekable OCI (lazy loading) | No | No | SOCI index after push |
| 06-cds | Class Data Sharing | Yes | No | Training run |
| 07-aot | Ahead-of-Time compilation | Yes | No | Training run |
| 08-native | GraalVM Native Image | No | No | Long build time |
| 09-crac | Coordinated Restore at Checkpoint | Yes | Yes | UnicornPublisher swap |

## Flow

### Build-only mode (default)

```
For each method:
  1. Pre-build hooks (CRaC: swap UnicornPublisher.crac)
  2. Start PostgreSQL if needed (CDS, AOT, CRaC)
  3. Build image (docker build or mvn jib:dockerBuild)
  4. Stop PostgreSQL
  5. Post-build hooks (CRaC: restore UnicornPublisher.java)
  6. Output: Method | ✅/❌ | Size | Time
```

### Deploy mode (`--deploy`)

```
┌─────────────────────────────────────────────────────────────────┐
│  MAIN PROCESS (build)              BACKGROUND WATCHER (deploy)  │
├─────────────────────────────────────────────────────────────────┤
│  Start watcher ──────────────────► Initialize results file      │
│                                                                 │
│  For each method:                                               │
│    Build image                                                  │
│    Push to ECR (:tag)                                          │
│    Write to queue ───────────────► Read queue                   │
│    Continue immediately            kubectl set image :tag       │
│                                    Wait for rollout             │
│                                    Record startup time          │
│                                    kubectl rollout restart      │
│                                    Record restart time          │
│                                    Write to results file        │
│                                                                 │
│  Write END marker ───────────────► kubectl set image :latest    │
│  Wait for watcher                  (revert to baseline)         │
│  Print final results               Exit                         │
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
Method         | Build | Size Local | Time
---------------|-------|------------|------
02-multi-stage | ✅    | 598MB      | 45s
06-cds         | ✅    | 1.34GB     | 2m15s
08-native      | ❌    | N/A        | 5m30s
```

### Deploy mode results file
```
Method         | Size Local | Size ECR | Build Time | Startup Time
---------------|------------|----------|------------|-------------
02-multi-stage | 598MB      | 580MB    | 45s        | 8.234 seconds
06-cds         | 1.34GB     | 1.2GB    | 2m15s      | 2.156 seconds
09-crac        | 1.1GB      | 1.0GB    | 3m20s      | 0.087 seconds
```

## Environment

Requires workshop environment (`/etc/profile.d/workshop.sh`) with:
- `ACCOUNT_ID` - AWS account ID
- `AWS_REGION` - AWS region
- `SPRING_DATASOURCE_URL` - Database connection string (for CDS/AOT/CRaC builds)
- `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD`

## Notes

- Build uses local PostgreSQL container for training (CDS, AOT, CRaC)
- Deploy uses real RDS database via Secrets Manager
- Native image may fail on ARM (macOS) - works on x86-64 Linux
- CRaC requires x86-64 for `-XX:CPUFeatures=generic`
- SOCI requires `soci` CLI tool installed
