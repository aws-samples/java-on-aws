# Coding Standards

## General Principles
- Prefer simple, explicit code over hidden magic
- Optimize for readability and maintainability
- Keep classes focused and cohesive
- Avoid unnecessary abstraction
- Prefer composition over deep inheritance

## Dependency Injection
- Prefer constructor injection
- Do not use field injection
- Keep bean wiring explicit where it improves clarity

## Class Design
- Keep public APIs small and intentional
- Avoid static mutable state
- Keep methods short enough to remain readable
- Extract helpers when they improve clarity, not just to reduce line count

## Error Handling
- Use structured exceptions
- Do not leak internal implementation details through API responses
- Map exceptions consistently at the API boundary

## Configuration
- Group related configuration into typed configuration classes
- Do not scatter configuration keys across the codebase
- Never hardcode secrets

## Logging
- Use structured, purposeful logging
- Do not log secrets, tokens, or sensitive personal data
- Log events that help with debugging and operations, not noise
