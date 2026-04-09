// Backoffice MCP Gateway Policy
// Forbid dangerous operations - everything else allowed by default

forbid(
  principal,
  action in [
    AgentCore::Action::"backoffice___cancelTrip",
    AgentCore::Action::"backoffice___deleteExpense"
  ],
  resource == AgentCore::Gateway::"${GATEWAY_ARN}"
);
