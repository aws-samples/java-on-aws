# API Standards

## API Design
- Build clear and predictable REST APIs
- Keep request and response models explicit
- Do not expose JPA entities directly from controllers
- Validate input at the API boundary

## Controllers
- Controllers must remain thin
- Controllers orchestrate request handling and delegate business logic to services
- Controllers must not contain persistence logic

## Validation
- Use Jakarta Bean Validation on request DTOs
- Reject invalid requests early and consistently

## Response Handling
- Use appropriate HTTP status codes
- Return stable response shapes
- Use a consistent error response format across the service

## Error Format
Error responses should include:
- a stable error code
- a human-readable message
- optional details when useful and safe
- request correlation information when available

## API Evolution
- Prefer additive changes
- Avoid breaking changes unless explicitly planned and documented
- Keep endpoint naming and resource modeling consistent
