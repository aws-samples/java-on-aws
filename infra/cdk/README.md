# Workshop Infrastructure

CDK project for generating CloudFormation templates for AWS workshops.

## Quick Start

```bash
# Generate all CloudFormation templates
npm run generate

# Sync templates to workshop directories
npm run sync
```

## Customization

Edit `WorkshopStack.java` to change the resource naming prefix:
```java
String prefix = "workshop";  // Change to customize all resource names
```

Then regenerate templates with `npm run generate`.

## Details

See `.kiro/specs/infra/` for complete requirements, design, and implementation details.
