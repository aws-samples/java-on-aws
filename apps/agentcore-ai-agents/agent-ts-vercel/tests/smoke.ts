// Smoke test for one assembled stage, without AWS: run from the stage directory with `npx tsx`.
// Mocks AWS API calls, starts the app on a test port, then checks /ping, the Web UI, the S3 artifact links,
// the conversation ID, (deploy stage) JWT handling and telemetry, and the tools of the later stages.
import assert from 'node:assert/strict';

process.env.AWS_REGION = 'us-east-1';
process.env.AWS_ACCESS_KEY_ID = 'test';
process.env.AWS_SECRET_ACCESS_KEY = 'test';
process.env.AGENTCORE_MEMORY_ID = 'mem-test';
process.env.KNOWLEDGE_BASE_ID = 'kb-test';
process.env.ARTIFACTS_BUCKET = 'workshop-bucket-test';
process.env.PORTAL_URL = 'https://portal.example.com';
process.env.PORT = process.env.PORT ?? '18099';

const { mockClient } = await import('aws-sdk-client-mock');
const control = await import('@aws-sdk/client-bedrock-agentcore-control');
const s3 = await import('@aws-sdk/client-s3');
const controlMock = mockClient(control.BedrockAgentCoreControlClient);
controlMock.on(control.GetMemoryCommand).resolves({
  memory: { strategies: [{ strategyId: 's1', namespaces: ['/strategies/{memoryStrategyId}/actors/{actorId}'] }] },
} as never);
controlMock.on(control.GetConfigurationBundleCommand).resolves({
  versionId: 'v1', components: { 'arn:runtime': { configuration: { system_prompt: 'Prompt from the bundle' } } },
} as never);
const agentcore = await import('@aws-sdk/client-bedrock-agentcore');
const agentcoreMock = mockClient(agentcore.BedrockAgentCoreClient);
const s3Mock = mockClient(s3.S3Client);
s3Mock.on(s3.PutObjectCommand).resolves({});
const runtime = await import('@aws-sdk/client-bedrock-runtime');
const guardrailMock = mockClient(runtime.BedrockRuntimeClient);

const stage = process.argv[2];
if (stage >= '11') {
  process.env.GUARDRAIL_ID = 'gr-test';
  process.env.GUARDRAIL_VERSION = '1';
}
if (stage >= '10') process.env.AUDITOR_HARNESS_ARN = 'arn:aws:bedrock-agentcore:us-east-1:123456789012:harness/auditor';
if (stage >= '12') process.env.CALENDAR_URL = 'https://calendar.example.com';
if (stage >= '15') process.env.CONFIG_BUNDLE_ID = 'bundle-test';
if (stage >= '09') process.env.COGNITO_ISSUER_URI = 'https://cognito-idp.us-east-1.amazonaws.com/pool';
const base = `http://127.0.0.1:${process.env.PORT}`;
await import(`${process.cwd()}/main.ts`);
for (let i = 0; i < 50; i++) {
  try { await fetch(`${base}/ping`); break; } catch { await new Promise((r) => setTimeout(r, 100)); }
}

assert.equal((await (await fetch(`${base}/ping`)).json()).status, 'Healthy', 'ping');
assert.equal((await fetch(`${base}/`)).status, 200, 'web ui');
assert.ok((await (await fetch(`${base}/chat.js`)).text()).includes('decodeEventData'), 'shared ui');

const { readFileSync } = await import('node:fs');
if (stage >= '06') {
  assert.ok(readFileSync('main.ts', 'utf8').includes('the corporate travel portal ${process.env.PORTAL_URL}'), 'portal line');
}

if (stage >= '03') {
  const memory = await import(`${process.cwd()}/memory.ts`);
  assert.deepEqual(memory.parse('alice:s1'), { actorId: 'alice', sessionId: 's1' }, 'memory parse');
  assert.deepEqual(memory.parse('alice'), { actorId: 'alice', sessionId: 'default-session' }, 'memory default session');
}

if (stage >= '06') {
  const artifacts = await import(`${process.cwd()}/artifacts.ts`);
  artifacts.currentSession.enterWith('alice:s1');
  artifacts.store('chart.png', new Uint8Array([137, 80]), 'image/png');
  artifacts.store('data.csv', new TextEncoder().encode('a,b'), 'text/csv');
  const md = await artifacts.asMarkdown('alice:s1');
  assert.ok(md.includes('![chart.png](https://workshop-bucket-test.s3') && md.includes('[Download data.csv](https://'), md);
  assert.ok(md.includes('X-Amz-Expires=3600') && s3Mock.commandCalls(s3.PutObjectCommand).length === 2, 's3 upload + presign');
}

if (stage >= '08') {
  delete process.env.GATEWAY_URL;
  const mcp = await import(`${process.cwd()}/mcp-tools.ts`);
  assert.deepEqual(await mcp.gatewayTools(), {}, 'no gateway without GATEWAY_URL');
}

if (stage >= '09') {
  const auth = await import(`${process.cwd()}/auth.ts`);
  const token = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from('{"sub":"user-123","username":"alice"}').toString('base64url')}.`;
  assert.equal(auth.conversationId({ sessionId: 'sess-1', headers: { authorization: `Bearer ${token}` } }), 'alice:sess-1', 'conversation id');
  assert.equal(auth.conversationId({ sessionId: 'alice', headers: { authorization: 'alice' } }), 'alice', 'local mode');
  const res = await fetch(`${base}/invocations`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Amzn-Bedrock-AgentCore-Runtime-Session-Id': 's' }, body: '{"prompt":"hi"}' });
  assert.equal(res.status, 401, 'jwt required');
  assert.equal((await fetch(`${base}/ping`)).status, 200, 'ping stays public');
}

if (stage >= '11') {
  const guardrail = await import(`${process.cwd()}/guardrail.ts`);
  assert.equal(guardrail.providerOptions.bedrock.guardrailConfig.guardrailIdentifier, 'gr-test', 'guardrail config');
  assert.deepEqual((guardrail.userMessage('hi').content[0] as any).providerOptions, { bedrock: { guardContent: true } }, 'guardContent');
  guardrailMock.on(runtime.ApplyGuardrailCommand)
    .resolvesOnce({ action: 'GUARDRAIL_INTERVENED', assessments: [{ contentPolicy: { filters: [{ type: 'PROMPT_ATTACK', action: 'BLOCKED' }] } }], outputs: [{ text: 'Sorry' }] } as never)
    .resolvesOnce({ action: 'GUARDRAIL_INTERVENED', assessments: [{ sensitiveInformationPolicy: { piiEntities: [] } }], outputs: [{ text: 'card {CREDIT_DEBIT_CARD_NUMBER}' }] } as never)
    .resolvesOnce({ action: 'GUARDRAIL_INTERVENED', assessments: [{ topicPolicy: { topics: [{ name: 'TaxAdvice', action: 'BLOCKED' }] } }], outputs: [{ text: 'Sorry' }] } as never);
  assert.equal(await guardrail.checkContent('page'), guardrail.BLOCKED_CONTENT, 'prompt attack blocked');
  assert.equal(await guardrail.maskPii('card 4111 1111 1111 1111'), 'card {CREDIT_DEBIT_CARD_NUMBER}', 'payment data masked');
  assert.equal(await guardrail.checkContent('tax page'), 'tax page', 'topics do not apply to tool output');
}

if (stage >= '09') {
  const dockerfile = readFileSync('Dockerfile', 'utf8');
  assert.ok(dockerfile.includes('aws-distro-opentelemetry-node-autoinstrumentation/register') && dockerfile.includes('./telemetry.ts'), 'ADOT');
  await import(`${process.cwd()}/telemetry.ts`);
}

if (stage >= '10') {
  const artifacts = await import(`${process.cwd()}/artifacts.ts`);
  const compliance = await import(`${process.cwd()}/compliance-tools.ts`);
  assert.deepEqual(Object.keys(compliance.complianceTools), ['check_compliance'], 'auditor tool');
  agentcoreMock.on(agentcore.InvokeHarnessCommand).resolves({
    stream: (async function* () {
      yield { messageStart: { role: 'assistant' } };
      yield { contentBlockDelta: { contentBlockIndex: 0, delta: { text: 'NOT COMPLIANT\n\nReport: ' } } };
      yield { contentBlockDelta: { contentBlockIndex: 0, delta: { text: '<https://b.s3.amazonaws.com/artifacts/1/audit-report.md?X-Amz-Signature=a>' } } };
    })(),
  } as never);
  artifacts.currentSession.enterWith('bob:s1');
  const answer = await compliance.complianceTools.check_compliance.execute!({ request: 'Business class to Tokyo' }, { toolCallId: '1', messages: [] });
  assert.ok(answer.startsWith('NOT COMPLIANT') && !answer.includes('https://'), answer);
  assert.equal((agentcoreMock.commandCalls(agentcore.InvokeHarnessCommand)[0].args[0].input.runtimeSessionId ?? '').length, 36, 'session id');
  assert.ok((await artifacts.asMarkdown('bob:s1')).includes('[Download audit-report.md](https://b.s3.amazonaws.com/artifacts/1/'), 'forwarded link');
}

if (stage >= '12') {
  const calendar = await import(`${process.cwd()}/calendar-tools.ts`);
  agentcoreMock.on(agentcore.GetWorkloadAccessTokenForUserIdCommand).resolves({ workloadAccessToken: 'wat-local' });
  agentcoreMock.on(agentcore.GetResourceOauth2TokenCommand).resolves({ authorizationUrl: 'https://auth.example.com/oauth2/authorize?x=1' });
  agentcoreMock.on(agentcore.CompleteResourceTokenAuthCommand).resolves({});
  const answer = await calendar.currentUser.run({ userId: 'alice', bearer: '' },
    () => calendar.calendarTools.get_calendar_events.execute!({}, { toolCallId: '1', messages: [] }));
  assert.ok(answer.includes('https://auth.example.com/oauth2/authorize'), answer);
  const tokenCall = agentcoreMock.commandCalls(agentcore.GetResourceOauth2TokenCommand)[0].args[0].input;
  assert.ok(tokenCall.workloadIdentityToken === 'wat-local' && tokenCall.oauth2Flow === 'USER_FEDERATION', 'local workload token');
  await calendar.currentUser.run({ userId: 'alice', bearer: '' }, () => calendar.completeAuthorization('urn:session'));
  await calendar.currentUser.run({ userId: 'u-1', bearer: 'Bearer jwt', workloadToken: 'wat' }, () => calendar.completeAuthorization('urn:session'));
  const [local, runtimeCall] = agentcoreMock.commandCalls(agentcore.CompleteResourceTokenAuthCommand).map((c) => c.args[0].input);
  assert.deepEqual([local.userIdentifier, runtimeCall.userIdentifier], [{ userId: 'alice' }, { userToken: 'jwt' }], 'consent user');
}

if (stage >= '13') {
  const attachments = await import(`${process.cwd()}/attachments.ts`);
  const message = await attachments.userMessage('Add this', { fileName: 'r.png', fileBase64: Buffer.from('x').toString('base64') });
  const [text, file] = message.content as any[];
  assert.ok(text.text.includes('S3 URI: s3://workshop-bucket-test/artifacts/uploads/') && file.mediaType === 'image/png', 'attachment');
  assert.equal((await attachments.userMessage('hi', {})).content.length, 1, 'no attachment');
}

if (stage >= '14') {
  const mcp = await import(`${process.cwd()}/mcp-tools.ts`);
  assert.deepEqual(await mcp.userGatewayTools('Bearer x'), {}, 'no JWT Gateway without JWT_GATEWAY_URL');
  process.env.JWT_GATEWAY_URL = 'https://jwt.example.com/mcp';
  assert.deepEqual(await mcp.userGatewayTools('alice'), {}, 'no JWT Gateway tools without a bearer token');
  delete process.env.JWT_GATEWAY_URL;
}

if (stage >= '15') {
  const promptConfig = await import(`${process.cwd()}/prompt-config.ts`);
  assert.equal(await promptConfig.systemPrompt('default'), 'Prompt from the bundle', 'bundle prompt');
  assert.equal(controlMock.commandCalls(control.GetConfigurationBundleCommand).length, 1, 'bundle cached');
  await promptConfig.systemPrompt('default');
  assert.equal(controlMock.commandCalls(control.GetConfigurationBundleCommand).length, 1, 'bundle read once a minute');
}

console.log(`${stage}: ok`);
process.exit(0);
