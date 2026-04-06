# Spring Boot Standards

## Core Principles
- Use Spring Boot conventions where they improve consistency
- Keep framework usage idiomatic but restrained
- Do not introduce Spring features without a clear need

## Web Stack
- Prefer Spring MVC by default
- Use WebFlux only when there is a clear non-blocking requirement
- Do not mix MVC and reactive patterns casually

## Configuration
- Use `@ConfigurationProperties` for grouped configuration
- Keep configuration classes focused
- Use profiles deliberately and sparingly

## Controllers and Services
- Use `@RestController` for HTTP APIs
- Keep controllers thin
- Put business logic in service classes
- Keep transactional boundaries in the service layer unless there is a strong reason otherwise

## Persistence
- Use Spring Data JPA only where it fits the domain and performance needs
- Do not expose repository behavior directly to the API layer
- Review fetch behavior consciously to avoid N+1 issues
- Keep database access patterns explicit enough to reason about performance

## Boot Features
- Use auto-configuration as a productivity feature, not as an excuse to hide important technical decisions
- Add starters intentionally
- Avoid unnecessary custom configuration when Spring Boot defaults are sufficient

## Actuator
- Enable health and metrics endpoints according to service needs
- Separate operational endpoints from business APIs
- Expose only what is required for the deployment environment
