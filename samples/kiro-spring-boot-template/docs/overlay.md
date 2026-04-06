# Using the Kiro Overlay in an Existing Spring Boot Project

## What the overlay is

The Kiro overlay is the `.kiro/` directory added to the root of a repository.

It is not an application framework layer. It does not change runtime behavior. It is an AI guidance layer for repository work.

Its purpose is to shape how Kiro understands and modifies the project.

## What the overlay contains

- `steering/`: local repository rules and design constraints
- `skills/`: reusable task instructions
- `hooks/`: automatic triggers for selected workflows

A particularly useful steering file is `architecture-principles.md`. It gives Kiro an explicit architecture model to preserve during implementation and refactoring instead of relying only on generic coding advice.

## What the overlay does not do

It does not:
- replace architectural documentation
- replace team code review
- replace tests
- replace build tooling
- replace application configuration

It complements those things by making Kiro repository-aware.

## How the overlay should be introduced

### 1. Start with the repository as it exists
Do not redesign the whole codebase just to fit the overlay.

Instead, make the overlay describe the project that actually exists, especially in:
- package structure
- controller/service boundaries
- testing conventions
- Spring Boot usage patterns

### 2. Treat steering as local truth
When Kiro generates or reviews code, the local steering files should reflect the rules the team truly wants enforced.

If the repository uses:
- `@ConfigurationProperties`
- Spring MVC
- DTO mapping in the service layer
- Testcontainers for persistence integration tests
- service-layer transaction boundaries
- no direct repository access from controllers

then the overlay should say that directly.

### 3. Keep the first version small
A small overlay is easier to validate. Start with the included files, then add more only when you see repeated needs.

## Example rollout

### Existing project
Suppose the repository already has this shape:

```text
src/main/java/com/acme/orders
  api/
  service/
  persistence/
  config/
```

Then the overlay should preserve that shape in `structure.md`.

If controllers are already thin and services own transactions, keep those rules.

If the project uses Spring MVC and JPA, the Spring Boot steering should say so explicitly.

### What to adapt first
Adjust these files first:

- `product.md`
- `structure.md`
- `spring-boot-standards.md`
- `architecture-principles.md`
- `review-checklist.md`

Everything else can remain close to the template until you learn where more precision is needed.

## How Kiro uses the overlay during work

### During endpoint implementation
Kiro reads the local steering, then uses the `implement-endpoint` skill to apply those rules.

### During reviews
Kiro reads the review checklist and Spring Boot standards, then evaluates the change against them.

### During refactoring
Kiro uses the `refactor-service` skill to preserve behavior while improving class boundaries, naming, and structure.

## Overlay maintenance model

The overlay should evolve when you see recurring patterns such as:
- Kiro repeatedly placing mapping logic in the wrong layer
- too many broad Spring tests
- repeated review comments about transaction boundaries
- repeated misuse of repositories from controllers

That is the right moment to sharpen steering or expand a skill.

## Anti-patterns

Avoid these overlay mistakes:

### Overwriting project reality
Do not force the repository into a structure it does not have unless you are actively refactoring toward that target.

### Excessive prose
Long steering files with repeated advice cost tokens and reduce clarity.

### Too many hooks
Hooks should be rare and useful. Too many hooks create noisy automation.

### Empty skills
Do not create skills you do not actually use.

## Practical rule

The overlay should make Kiro more predictable, not more complicated.

If a steering rule, skill, or hook is not improving real output, remove it or simplify it.
