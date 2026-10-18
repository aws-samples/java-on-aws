// Loaded before main.ts in the container (`--import ./telemetry.ts` in the Dockerfile), after ADOT has registered the OpenTelemetry SDK
import { OpenTelemetry } from '@ai-sdk/otel';
import { propagation, trace } from '@opentelemetry/api';
import { registerTelemetry } from 'ai';

// >> Every AI SDK call emits spans with the GenAI semantic conventions (invoke_agent, chat, execute_tool)
registerTelemetry(
  new OpenTelemetry({
// <<
    // >> AgentCore Evaluations reads GenAI spans from scopes that start with `opentelemetry.instrumentation.`
    tracer: trace.getTracer('opentelemetry.instrumentation.vercel_ai'),
    // <<
    // >> AgentCore Runtime sends the session ID as W3C baggage; `session.id` groups the spans of a session
    enrichSpan: () => {
      const sessionId = propagation.getActiveBaggage()?.getEntry('session.id')?.value;
      return sessionId ? { 'session.id': sessionId } : undefined;
    },
    // <<
  }),
);
