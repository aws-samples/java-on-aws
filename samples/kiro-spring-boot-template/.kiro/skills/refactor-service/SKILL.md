---
name: refactor-service
description: Refactor a Spring Boot service class for clarity, cohesion, and maintainability without changing behavior.
---

# Purpose
Improve the internal structure of a Spring Boot service class while preserving externally visible behavior.

# Use This Skill When
- a service class is too large
- responsibilities are mixed
- transaction boundaries are unclear
- naming and flow make the code hard to review or extend
- repeated logic should be extracted safely

# Instructions
1. Read:
   - `.kiro/steering/structure.md`
   - `.kiro/steering/coding-standards.md`
   - `.kiro/steering/testing-standards.md`
   - `.kiro/steering/spring-boot-standards.md`
   - `.kiro/steering/review-checklist.md`

2. Preserve behavior first:
   - do not change public API behavior unless explicitly requested
   - retain validation, transaction semantics, and error behavior
   - add or strengthen tests before risky structural changes when needed

3. Refactor toward:
   - smaller, cohesive methods
   - clearer names
   - reduced duplication
   - explicit dependencies
   - better separation of orchestration, domain logic, and mapping

4. Keep Spring Boot usage disciplined:
   - leave controllers thin
   - keep transactional boundaries intentional
   - avoid moving repository access into controllers or unrelated layers
   - do not introduce new framework abstractions without a strong reason

5. Prefer incremental structural improvements over broad rewrites.

6. If extraction is needed, consider introducing:
   - helper methods
   - mapper components
   - focused collaborator services
   - domain-oriented value objects

7. Update tests to protect behavior where the refactoring meaningfully changes internal structure.

# Output Expectations
A good result usually includes:
- smaller and clearer service logic
- preserved behavior
- improved naming
- less duplication
- tests that reduce refactoring risk

# Avoid
- changing behavior accidentally during cleanup
- introducing extra layers without payoff
- replacing straightforward code with abstract patterns
- broad rewrites without sufficient test protection
