# Cedar policy: Permit all tools EXCEPT cancelTrip and deleteExpense for user alice
#
# Uses 'unless' clause to deny specific tools while permitting all others.
# This approach works around AgentCore's "Overly Restrictive" safety check
# that rejects standalone 'forbid' policies.

permit(
  principal is AgentCore::OAuthUser,
  action,
  resource == AgentCore::Gateway::"arn:aws:bedrock-agentcore:us-east-1:724772082315:gateway/policy-demo-gateway-wwh6rjluyl"
) when {
  principal.hasTag("username") &&
  principal.getTag("username") == "alice"
} unless {
  action == AgentCore::Action::"backoffice___cancelTrip" ||
  action == AgentCore::Action::"backoffice___deleteExpense"
};
