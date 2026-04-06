# Review Checklist

Use this checklist for implementation and review work.

## Architecture
- Is business logic outside controllers?
- Are package boundaries respected?
- Are DTOs separated from persistence entities?

## Spring Boot Usage
- Is Spring Boot used idiomatically?
- Is `@SpringBootTest` only used where justified?
- Is configuration modeled with `@ConfigurationProperties` where appropriate?

## API Quality
- Are input validation and HTTP status codes correct?
- Is error handling consistent?
- Are response models explicit and stable?

## Persistence
- Are transactional boundaries sensible?
- Is repository usage appropriate and not leaking into controllers?
- Are obvious performance risks such as N+1 considered?

## Code Quality
- Is the code easy to read and change?
- Are abstractions justified?
- Is logging useful and safe?

## Testing
- Are the right kinds of tests present?
- Do tests verify business behavior, not just framework mechanics?
- Are important edge cases covered?
