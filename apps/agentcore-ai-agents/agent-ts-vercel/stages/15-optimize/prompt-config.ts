import {
  BedrockAgentCoreControlClient, GetConfigurationBundleCommand, GetConfigurationBundleVersionCommand,
} from '@aws-sdk/client-bedrock-agentcore-control';
import { propagation } from '@opentelemetry/api';

const CONFIG_BUNDLE_ID = process.env.CONFIG_BUNDLE_ID;

const control = new BedrockAgentCoreControlClient({ region: process.env.AWS_REGION });
const latest = { readAt: 0, systemPrompt: undefined as string | undefined };
const versions = new Map<string, Promise<string | undefined>>();

// The system prompt of the bundle: one component (this runtime) with free-form JSON configuration
function systemPromptOf(components: Record<string, { configuration?: unknown }> | undefined) {
  const [component] = Object.values(components ?? {});
  return (component?.configuration as { system_prompt?: string } | undefined)?.system_prompt;
}

async function latestSystemPrompt() {
  // >> The latest version of the bundle, read at most once a minute
  if (Date.now() - latest.readAt > 60_000) {
    const bundle = await control.send(new GetConfigurationBundleCommand({ bundleId: CONFIG_BUNDLE_ID }));
    latest.readAt = Date.now();
    latest.systemPrompt = systemPromptOf(bundle.components);
  }
  // <<
  return latest.systemPrompt;
}

// >> During an A/B test the Gateway passes the session's variant (a bundle version) as W3C baggage
function abTestSystemPrompt() {
  const baggage = propagation.getActiveBaggage();
  const bundleArn = baggage?.getEntry('aws.agentcore.configbundle_arn')?.value;
  const versionId = baggage?.getEntry('aws.agentcore.configbundle_version')?.value;
  if (!bundleArn || !versionId) {
    return undefined;
  }
  if (!versions.has(versionId)) {
    versions.set(versionId, control.send(new GetConfigurationBundleVersionCommand({ bundleId: bundleArn.split('/').pop(), versionId }))
      .then((version) => systemPromptOf(version.components)));
  }
  return versions.get(versionId);
}
// <<

// The system prompt for this request: from the configuration bundle when `CONFIG_BUNDLE_ID` is set, otherwise the default
export async function systemPrompt(defaultPrompt: string) {
  if (!CONFIG_BUNDLE_ID) {
    return defaultPrompt;
  }
  return (await abTestSystemPrompt()) ?? (await latestSystemPrompt()) ?? defaultPrompt;
}
