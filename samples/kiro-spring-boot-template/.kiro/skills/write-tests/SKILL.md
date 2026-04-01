---
name: write-tests
description: Add or improve tests for Spring Boot code changes using the smallest suitable test scope.
---

# Purpose
Write focused tests for newly added or changed code in this Spring Boot repository.

# Use This Skill When
- business logic changed
- controller behavior changed
- persistence behavior changed
- regression protection is needed

# Instructions
1. Read:
   - `.kiro/steering/testing-standards.md`
   - `.kiro/steering/spring-boot-standards.md`
   - `.kiro/steering/review-checklist.md`

2. Choose the smallest suitable test scope:
   - plain unit tests for business logic
   - MVC or repository integration tests where framework behavior matters
   - `@SpringBootTest` only when full bootstrapping is necessary

3. Test for behavior, not just line execution.

4. Cover:
   - success path
   - relevant validation failures
   - important edge cases
   - meaningful error conditions

5. Keep test setup readable.
6. Avoid unnecessary fixtures and brittle mocks.
7. Prefer clear assertions over clever abstractions.

# Output Expectations
A good result includes:
- the right test type
- clear scenario naming
- focused setup
- assertions that prove behavior

# Avoid
- broad, slow tests without clear need
- framework-heavy tests for simple pure logic
- superficial tests with no meaningful assertions
