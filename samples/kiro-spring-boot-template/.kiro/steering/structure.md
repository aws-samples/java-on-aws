# Project Structure

## Package Layout
Use a package structure that keeps API, business logic, and infrastructure concerns separate.

Preferred package layout:

- `...api` for controllers, request/response DTOs, and exception handlers
- `...service` for business logic
- `...domain` for domain models and core business concepts
- `...persistence` for repositories and persistence mappings
- `...config` for Spring configuration and typed properties
- `...integration` for external system clients

## Rules
- Keep controllers thin
- Do not place business logic in controllers
- Do not mix API DTOs with persistence entities
- Keep infrastructure concerns out of domain classes
- Prefer cohesive packages over technical dumping grounds such as `util` or `common`

## Example
```text
src/main/java/com/example/orders
  api/
  service/
  domain/
  persistence/
  config/
  integration/
```
