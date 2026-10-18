import {
  BedrockAgentCoreClient, CreateEventCommand, ListEventsCommand, RetrieveMemoryRecordsCommand,
} from '@aws-sdk/client-bedrock-agentcore';
import { BedrockAgentCoreControlClient, GetMemoryCommand } from '@aws-sdk/client-bedrock-agentcore-control';
import type { ModelMessage } from 'ai';

// >> Memory ID from `~/environment/.envrc`
const MEMORY_ID = process.env.AGENTCORE_MEMORY_ID!;
// <<
const data = new BedrockAgentCoreClient({ region: process.env.AWS_REGION });
const control = new BedrockAgentCoreControlClient({ region: process.env.AWS_REGION });

// >> Discover LTM strategy namespaces at startup — no need to save individual strategy IDs
const memory = await control.send(new GetMemoryCommand({ memoryId: MEMORY_ID }));
const namespaces = (memory.memory?.strategies ?? []).flatMap((s) =>
  (s.namespaces ?? []).map((ns) => ns.replace('{memoryStrategyId}', s.strategyId!)));
// <<

// >> The session header has the format `actorId` or `actorId:sessionId`
export function parse(conversationId: string) {
  const [actorId, sessionId = 'default-session'] = conversationId.split(/:(.*)/s);
  return { actorId, sessionId };
}
// <<

// >> Short-term memory: the conversation turns of this session, oldest first
export async function history(actorId: string, sessionId: string): Promise<ModelMessage[]> {
  const res = await data.send(new ListEventsCommand({ memoryId: MEMORY_ID, actorId, sessionId, includePayloads: true, maxResults: 50 }));
  return (res.events ?? [])
    .sort((a, b) => a.eventTimestamp!.getTime() - b.eventTimestamp!.getTime())
    .flatMap((e) => e.payload ?? [])
    .flatMap((p) => (p.conversational ? [p.conversational] : []))
    .map((c) => ({ role: c.role === 'USER' ? 'user' : 'assistant', content: c.content!.text! }) as ModelMessage);
}
// <<

// >> Long-term memory: facts and preferences of the actor that are relevant to the question
export async function facts(actorId: string, question: string): Promise<string[]> {
  const results = await Promise.all(namespaces.map((ns) => data.send(new RetrieveMemoryRecordsCommand({
    memoryId: MEMORY_ID, namespace: ns.replace('{actorId}', actorId), searchCriteria: { searchQuery: question, topK: 3 },
  }))));
  return results.flatMap((r) => r.memoryRecordSummaries ?? []).map((r) => r.content?.text ?? '').filter(Boolean);
}
// <<

// >> Save the turn as conversational events; the strategies extract long-term memory from them
export async function save(actorId: string, sessionId: string, user: string, assistant: string) {
  await data.send(new CreateEventCommand({
    memoryId: MEMORY_ID, actorId, sessionId, eventTimestamp: new Date(),
    payload: [
      { conversational: { role: 'USER', content: { text: user } } },
      { conversational: { role: 'ASSISTANT', content: { text: assistant } } },
    ],
  }));
}
// <<
