# Architecture Principles

## Purpose
This document defines the repository-level Spring Boot architecture principles that Kiro should preserve and reinforce during implementation, review, and refactoring work.

## Layering Model
Use a clear layered service architecture:
- `api` handles HTTP concerns, request validation, DTO mapping at the boundary, and response construction
- `service` contains business use cases and transactional orchestration
- `domain` contains business concepts and domain rules when applicable
- `persistence` contains repositories and persistence mappings
- `integration` contains clients for external systems
- `config` contains typed configuration and Spring wiring

## Enforced Boundaries
- Controllers must not contain business rules
- Controllers must not call repositories directly
- Repositories must not be exposed directly to the API layer
- External client calls must not be embedded in controllers
- Transaction boundaries should normally live in the service layer
- Persistence entities must not be used as public API contracts

## Dependency Direction
Prefer inward-facing dependencies:
- `api` may depend on `service`
- `service` may depend on `domain`, `persistence`, and `integration`
- `persistence` must not depend on `api`
- `domain` should stay as independent as practical from Spring and infrastructure details

## Spring Boot Architectural Use
- Prefer Spring MVC unless reactive behavior is an explicit architectural requirement
- Use `@ConfigurationProperties` for grouped configuration
- Keep auto-configuration benefits, but do not hide important technical decisions
- Keep application wiring explicit enough that maintainers can understand flow and ownership

## API Architecture
- Use DTOs for request and response models
- Validate input at the API boundary
- Keep error handling consistent through centralized exception mapping or equivalent repository conventions
- Keep controllers as orchestration endpoints, not workflow engines

## Persistence Architecture
- Keep repository interfaces focused on aggregate access and query intent
- Avoid leaking persistence concerns into business APIs
- Review fetch behavior and query design consciously for performance-sensitive paths
- Keep database transactions small and explicit enough to reason about

## Integration Architecture
- Isolate external system access in dedicated integration components
- Keep retry, timeout, and mapping behavior out of controllers
- Translate external payloads into internal models before business logic depends on them

## Evolution Principles
- Prefer additive architectural evolution over frequent structural churn
- Refactor toward clearer boundaries when responsibilities become mixed
- Add abstractions only when they reduce repeated complexity or clarify ownership
- Optimize for maintainability and operability, not architectural novelty
