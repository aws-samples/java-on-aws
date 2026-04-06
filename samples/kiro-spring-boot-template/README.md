# Kiro Spring Boot Template

A lean Kiro setup for Spring Boot services.

This template is designed to give Kiro enough structure to produce consistent, reviewable output without becoming heavy, noisy, or expensive in token usage. It uses a small local steering layer, a minimal hook set, and a focused skill set for the most common service development tasks.

## Goals

- Keep service implementations consistent across repositories
- Make endpoint work, testing, review, and refactoring more predictable
- Avoid over-engineered steering hierarchies and large framework matrices
- Give Kiro clear local guidance for Spring Boot projects
- Provide a reusable overlay that can be copied into an existing repository

## What Is Included

```text
.kiro/
  steering/
    product.md
    structure.md
    coding-standards.md
    api-standards.md
    testing-standards.md
    spring-boot-standards.md
    architecture-principles.md
    review-checklist.md
  hooks/
    review-on-pr.yaml
    test-on-service-change.yaml
  skills/
    implement-endpoint/
      SKILL.md
    write-tests/
      SKILL.md
    review-pr/
      SKILL.md
    refactor-service/
      SKILL.md
docs/
  overlay.md
README.md
```

## Design Principles

### Lean over comprehensive
The template intentionally avoids a large multi-framework steering hierarchy. It focuses on one stack: Spring Boot.

### Local steering over global prose
The most valuable Kiro guidance is repository-local. The files in `.kiro/steering/` are the primary source of truth for implementation behavior inside the project.

### Small number of hooks
Hooks are useful, but easy to overdo. This template includes only two:
- review on PR open
- test suggestion on meaningful code changes

### Skills for real work
The skills map to high-value development tasks:
- implement a REST endpoint
- write tests using the smallest suitable scope
- review a pull request
- refactor a service without changing behavior

### Architecture guidance is explicit
The template includes `architecture-principles.md` so Kiro can enforce repository-level Spring Boot architectural boundaries such as controller/service/repository separation, dependency direction, transaction placement, and DTO/entity separation.

## Installation

### Option 1: Start a new repository from this template
1. Create a new Spring Boot repository.
2. Copy the `.kiro/` directory into the repository root.
3. Copy `README.md` sections you want to keep, or keep this file as the repository Kiro guide.
4. Adjust `product.md` and `structure.md` to match the service.
5. Commit the initial Kiro setup.

### Option 2: Use this as an overlay for an existing repository
1. Open your existing Spring Boot repository.
2. Copy the `.kiro/` directory into the repository root.
3. Review and update these files first:
   - `.kiro/steering/product.md`
   - `.kiro/steering/structure.md`
   - `.kiro/steering/spring-boot-standards.md`
4. Keep the rest as-is unless the repository has strong, explicit differences.
5. Commit the overlay as a dedicated change.

The overlay approach is usually the better starting point because it lets you add Kiro guidance without restructuring the whole project.

## Recommended First Customizations

After copying the template, update these areas before broad usage:

### `product.md`
Describe the service purpose, deployment assumptions, and non-goals.

### `structure.md`
Align the package layout with the actual repository.

### `spring-boot-standards.md`
Adjust for MVC vs WebFlux, persistence style, Actuator exposure, and configuration patterns.

### `architecture-principles.md`
Align the architectural boundaries with the real service design, especially controller/service/repository separation, dependency direction, and transaction ownership.

### `review-checklist.md`
Add repository-specific review checks if the team repeatedly catches the same problems.

## Usage

### Implementing an endpoint
Use the `implement-endpoint` skill when adding or extending a REST endpoint. The skill reads the steering files, keeps controllers thin, delegates to services, uses DTOs, and expects suitable tests.

Example task prompts:
- `Implement a POST /orders endpoint that validates the request, creates an order through the service layer, and returns 201 with an OrderResponse DTO.`
- `Extend the existing GET /orders/{id} endpoint to return 404 with the standard error model when the order is missing.`

### Writing tests
Use the `write-tests` skill when adding behavior or fixing regressions. It prefers the smallest correct test scope.

Example task prompts:
- `Write focused tests for OrderService#createOrder covering the success case, invalid quantity, and duplicate order detection.`
- `Add MVC tests for OrdersController request validation and 404 handling.`

### Reviewing a PR
Use the `review-pr` skill manually or let the PR hook trigger it automatically.

Example task prompts:
- `Review this PR against the local Kiro steering. Focus on controller/service boundaries, validation, transaction placement, and test scope.`
- `Review the order endpoint changes and report only actionable findings, ordered by severity.`

### Refactoring a service
Use the `refactor-service` skill when a service class has become too large, hard to understand, or is mixing responsibilities.

Example task prompts:
- `Refactor OrderService to separate pricing, validation, and persistence orchestration without changing behavior.`
- `Refactor this service so repository access stays in the service layer, mapping is clearer, and the public behavior remains unchanged.`

## Hooks

### `review-on-pr.yaml`
Triggers the `review-pr` skill when a pull request is opened.

### `test-on-service-change.yaml`
Triggers the `write-tests` skill when Java files in service, API, or persistence paths change.

These hooks are intentionally narrow. They should support the workflow, not dominate it.

## How the Overlay Works with a Project

The `.kiro/` directory acts as a repository-local overlay.

It does not replace your application code, build files, or test structure. Instead, it sits alongside the project and tells Kiro how to reason about that codebase.

Think of it as an instruction layer with three jobs:

1. Steering tells Kiro what “good” looks like in this repository.
2. Architecture principles tell Kiro which boundaries and dependency directions must be preserved.
3. Skills tell Kiro how to execute common tasks.
4. Hooks tell Kiro when to apply those skills automatically.

When Kiro works inside a repository, the overlay shapes its output by adding project-local standards on top of general model behavior.

### Overlay behavior in practice

If a project already has:
- existing package structure
- custom exception handling
- repository-specific test conventions
- a preferred Spring Boot style

then the overlay should be adapted to reflect those realities, not fight them.

That is why this template is intentionally small. A small overlay is easier to align with a real project.

### Good overlay strategy

Use the template as a base, then tune only where the repository genuinely differs.

Good examples:
- update package examples in `structure.md`
- add explicit persistence rules if JPA usage is complex
- add observability guidance if the service uses Actuator and OpenTelemetry heavily

Bad examples:
- copying long generic engineering manifestos into steering files
- duplicating Spring Boot advice in five different places
- adding hooks for every possible event before real usage data exists

For a fuller explanation, see `docs/overlay.md`.

## Recommended Rollout Strategy

1. Add the overlay to one Spring Boot repository.
2. Use it for real endpoint, test, review, and refactoring work.
3. Observe where Kiro output is strong or inconsistent.
4. Tighten steering only where recurring issues appear.
5. Promote the refined version to other repositories.

## Why There Is No Global Steering in This Template

Global steering can be useful, but it is easy to make it too abstract or too verbose. This template focuses on the repository-local layer because that is where the strongest guidance comes from.

If you want a global layer, keep it short. Use it for a few durable engineering principles, not framework detail.