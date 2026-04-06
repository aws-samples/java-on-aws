---
name: implement-endpoint
description: Implement a Spring Boot REST endpoint aligned with local steering.
---

# Purpose
Implement a new REST endpoint in this Spring Boot service in a way that respects the repository steering.

# Use This Skill When
- A new HTTP endpoint is requested
- An existing endpoint needs to be extended
- A controller, DTO, service method, and related wiring need to be created

# Inputs
Expect the task to define:
- endpoint purpose
- HTTP method
- request shape
- response shape
- validation rules
- service behavior
- persistence impact, if any

# Instructions
1. Read the relevant steering files before making changes:
   - `.kiro/steering/structure.md`
   - `.kiro/steering/coding-standards.md`
   - `.kiro/steering/api-standards.md`
   - `.kiro/steering/testing-standards.md`
   - `.kiro/steering/spring-boot-standards.md`
   - `.kiro/steering/review-checklist.md`

2. Implement the endpoint using Spring MVC by default:
   - use `@RestController`
   - place request mapping in the API layer
   - keep controller logic thin
   - delegate business behavior to a service class

3. Create or update:
   - request DTOs
   - response DTOs
   - controller method
   - service method
   - repository interaction only if required

4. Apply validation at the API boundary with Bean Validation.

5. Do not expose entities directly in responses.

6. Add or update tests appropriate to the change:
   - unit tests for business logic
   - controller or integration tests only where needed

7. Keep the implementation small, explicit, and easy to review.

# Output Expectations
A good result usually includes:
- controller changes
- DTOs
- service changes
- tests
- consistent error handling

# Avoid
- business logic in controllers
- field injection
- `@SpringBootTest` without real need
- direct entity exposure
- overengineering for simple CRUD
