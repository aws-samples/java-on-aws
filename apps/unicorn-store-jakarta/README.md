# Unicorn Store - Jakarta EE + Quarkus/WildFly

A REST API and Web UI for managing unicorns, built with Jakarta EE. Can be deployed on either Quarkus or WildFly.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      HTTP Request                           │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  Web UI (PrimeFaces)    │     │  REST API (JAX-RS)      │
│  /webui/unicorns.xhtml  │     │  /unicorns              │
└─────────────────────────┘     └─────────────────────────┘
              │                               │
              └───────────────┬───────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  UnicornService                                             │
│  - Business logic, validation                               │
│  - Publishes events to EventBridge                          │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  UnicornRepository      │     │  UnicornPublisher       │
│  - JPA EntityManager    │     │  - EventBridge async    │
│  - PostgreSQL           │     │  - CRUD events          │
└─────────────────────────┘     └─────────────────────────┘
```

## Project Structure

```
unicorn-store-jakarta/
├── pom.xml                           # WildFly build (WAR)
├── quarkus/
│   ├── pom.xml                       # Quarkus build
│   ├── Dockerfile                    # Quarkus container
│   └── docker-compose.yml            # Local dev environment
├── wildfly/
│   ├── pom-galleon.xml               # WildFly Galleon provisioning
│   ├── Dockerfile                    # WildFly container
│   ├── datasource.cli                # WildFly datasource config
│   └── docker-compose.yml            # Local dev environment
└── src/main/
    ├── java/com/unicorn/store/
    │   ├── controller/
    │   │   ├── UnicornController.java    # JAX-RS REST endpoints
    │   │   ├── HelloController.java      # Welcome endpoint
    │   │   └── RestApplication.java      # JAX-RS application config
    │   ├── service/
    │   │   └── UnicornService.java       # Business logic
    │   ├── data/
    │   │   ├── UnicornRepository.java    # JPA repository
    │   │   └── UnicornPublisher.java     # EventBridge integration
    │   ├── model/
    │   │   ├── Unicorn.java              # JPA entity
    │   │   └── UnicornEventType.java     # Event type enum
    │   ├── exceptions/
    │   │   └── ResourceNotFoundException.java
    │   └── webui/
    │       └── UnicornPresenter.java     # JSF managed bean
    ├── resources/
    │   └── application.properties        # Quarkus configuration
    └── webapp/
        ├── webui/
        │   └── unicorns.xhtml            # PrimeFaces UI
        └── WEB-INF/
            ├── beans.xml                 # CDI configuration
            ├── faces-config.xml          # JSF configuration
            └── web.xml                   # Servlet configuration
```

## Runtime Options

| Runtime | Java Version | Description |
|---------|--------------|-------------|
| **Quarkus** | 21 | Lightweight, fast startup, cloud-native |
| **WildFly** | 21 | Full Jakarta EE application server |

## Building

### Quarkus (Recommended for containers)

```bash
cd quarkus
mvn clean package

# Or build container directly
docker build -f Dockerfile -t unicorn-store-jakarta:latest ..
```

### WildFly

```bash
mvn clean package

# Or build container
docker build -f wildfly/Dockerfile -t unicorn-store-wildfly:latest .
```

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Jakarta EE | 10.0.0 | Enterprise Java APIs |
| Quarkus | 3.22.1 | Runtime framework |
| PrimeFaces | 15.0.0 | JSF UI components |
| MyFaces | 4.1.1 | JSF implementation (Quarkus) |
| AWS SDK | 2.31.34 | EventBridge integration |
| PostgreSQL | runtime | Database driver |

## API Endpoints

### REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Welcome message |
| GET | `/unicorns` | List all unicorns |
| POST | `/unicorns` | Create unicorn |
| GET | `/unicorns/{id}` | Get by ID |
| PUT | `/unicorns/{id}` | Update unicorn |
| DELETE | `/unicorns/{id}` | Delete unicorn |

### Web UI

| Path | Description |
|------|-------------|
| `/webui/unicorns.xhtml` | Unicorn management UI |

### Health (Quarkus)

| Path | Description |
|------|-------------|
| `/q/health` | Combined health check |
| `/q/health/live` | Liveness probe |
| `/q/health/ready` | Readiness probe |

## Configuration

### Quarkus (Environment Variables)

| Variable | Description | Default |
|----------|-------------|---------|
| `QUARKUS_DATASOURCE_JDBC_URL` | PostgreSQL connection URL | - |
| `QUARKUS_DATASOURCE_USERNAME` | Database username | postgres |
| `QUARKUS_DATASOURCE_PASSWORD` | Database password | - |

### WildFly

Database configuration is done via `datasource.cli` which configures a JNDI datasource.

## Local Development

### Using Docker Compose (Quarkus)

```bash
cd quarkus
docker-compose up
```

### Using Docker Compose (WildFly)

```bash
cd wildfly
docker-compose up
```

## Container Images

### Quarkus Dockerfile

- Multi-stage build with Amazon Corretto 21
- Lightweight runtime (~200MB)
- Runs as non-root user (UID 1000)

### WildFly Dockerfile

- Multi-stage build with Amazon Corretto 21
- Full WildFly 37 application server
- PostgreSQL JDBC driver auto-configured
- Runs as non-root user (UID 1000)

## Web UI Features

The PrimeFaces UI provides:

- **Data Table**: Paginated list of all unicorns
- **Create**: Add new unicorns via dialog
- **Edit**: Modify existing unicorns
- **Delete**: Remove unicorns with confirmation
- **Responsive**: Works on mobile devices

## Comparison with Spring Version

| Feature | Jakarta/Quarkus | Spring Boot |
|---------|-----------------|-------------|
| Java Version | 21 | 25 |
| Framework | Quarkus + Jakarta EE | Spring Boot 4 |
| Web UI | ✅ PrimeFaces | ❌ API only |
| REST | JAX-RS | Spring MVC |
| DI | CDI | Spring DI |
| ORM | JPA/Hibernate | Spring Data JPA |
| Health | `/q/health` | `/actuator/health` |
| Config | `application.properties` | `application.yaml` |
