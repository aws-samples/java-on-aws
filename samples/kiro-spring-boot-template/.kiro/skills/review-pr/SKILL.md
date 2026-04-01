---
name: review-pr
description: Review Spring Boot code changes against repository steering and provide actionable findings.
---

# Purpose
Review changes in this repository for architectural consistency, Spring Boot best practices, test quality, and maintainability.

# Use This Skill When
- a pull request is opened
- a feature is completed
- a refactoring should be checked before merge

# Instructions
1. Read:
   - `.kiro/steering/coding-standards.md`
   - `.kiro/steering/api-standards.md`
   - `.kiro/steering/testing-standards.md`
   - `.kiro/steering/spring-boot-standards.md`
   - `.kiro/steering/review-checklist.md`

2. Review for:
   - controller/service/repository separation
   - appropriate Spring Boot usage
   - correct validation and error handling
   - reasonable transactional boundaries
   - test quality and scope
   - readability and maintainability

3. Report findings in order of importance:
   - correctness risks
   - architectural issues
   - maintainability concerns
   - test gaps
   - smaller cleanup suggestions

4. Be specific and actionable.
5. Prefer concrete fixes over vague commentary.

# Output Format
Structure findings like this:
- Severity
- Problem
- Why it matters
- Recommended change

# Avoid
- style nitpicks without practical value
- generic praise without substance
- asking for unnecessary abstractions
