# Testing Standards

## Philosophy
- Test business logic at the lowest reasonable level
- Use fast tests by default
- Use Spring context tests only when framework integration matters

## Test Types
### Unit Tests
Use plain unit tests for:
- business rules
- domain logic
- transformations
- validation logic not tied to Spring wiring

### Spring Slice or Integration Tests
Use Spring-based tests for:
- controller behavior
- serialization and validation integration
- persistence integration
- configuration wiring

### Full Application Tests
Use `@SpringBootTest` only when full application bootstrapping is necessary.

## Rules
- Do not default to `@SpringBootTest`
- Prefer focused tests over broad end-to-end style tests inside the service repository
- Use Testcontainers when realistic infrastructure integration is required
- Keep test data readable and localized to the test

## Coverage Expectations
- Critical business paths must be covered
- Edge cases should be covered where failure would be costly
- Avoid superficial tests that only exercise framework behavior without asserting business value
