# Product Context

## Purpose
This repository contains a Spring Boot service intended for production use in a cloud-native environment.

## Primary Goals
- Deliver business functionality through clear and maintainable APIs
- Keep service logic easy to understand and change
- Support reliable operation in containerized and CI/CD-driven environments
- Favor consistency over cleverness

## Architectural Assumptions
- The service is stateless unless explicitly documented otherwise
- Configuration is externalized
- The service is designed for automated deployment
- Observability and testability are first-class concerns

## Non-Goals
- Do not introduce unnecessary architectural layers
- Do not optimize prematurely
- Do not add framework features without a clear use case
