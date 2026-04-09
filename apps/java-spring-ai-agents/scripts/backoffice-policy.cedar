// Backoffice MCP Gateway Policy
// Cedar is deny-by-default, so we need permit-all first, then forbid specific actions

// Permit all actions on the gateway (required - Cedar denies by default)
permit(
  principal,
  action,
  resource == AgentCore::Gateway::"${GATEWAY_ARN}"
);

// Forbid dangerous operations (takes precedence over permit)
forbid(
  principal,
  action in [
    AgentCore::Action::"backoffice___cancelTrip",
    AgentCore::Action::"backoffice___deleteExpense"
  ],
  resource == AgentCore::Gateway::"${GATEWAY_ARN}"
);
