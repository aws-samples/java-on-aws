# Debugging Notes

## AWS CLI + .env Workflow

For debugging CloudWatch logs and AWS resources:

```bash
# Use .env credentials for immediate AWS CLI access
source .env && aws logs get-log-events --log-group-name "ide-bootstrap-YYYYMMDD-HHMMSS" --log-stream-name "i-instanceid" --start-from-head --output text
```

**Important**: Always use this approach instead of asking user for log content. The .env file contains AWS credentials for direct access.

## Usage Pattern
- Source .env first: `source .env`
- Use AWS CLI directly for logs, CloudFormation status, etc.
- Don't ask user to copy/paste log content