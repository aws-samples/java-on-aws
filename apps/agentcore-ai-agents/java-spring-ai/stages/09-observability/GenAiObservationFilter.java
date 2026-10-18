package com.example.agent;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import io.micrometer.common.KeyValue;
import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationFilter;
import org.springframework.ai.chat.client.observation.ChatClientObservationContext;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.MessageType;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.observation.ChatModelObservationContext;
import org.springframework.ai.tool.observation.ToolCallingObservationContext;
import tools.jackson.databind.json.JsonMapper;

/**
 * Adds the OpenTelemetry GenAI semantic convention attributes that AgentCore Evaluations reads to the
 * Spring AI observations: the ChatClient call becomes the invoke agent span, each model call an inference
 * span with its messages, and each tool call an execute tool span with arguments and result.
 */
public class GenAiObservationFilter implements ObservationFilter {

    private static final JsonMapper JSON = JsonMapper.builder().build();

    @Override
    public Observation.Context map(Observation.Context context) {
        // >> Evaluations group the spans of a session by `session.id`, the AgentCore Runtime session ID
        if (context instanceof ChatClientObservationContext || context instanceof ChatModelObservationContext
                || context instanceof ToolCallingObservationContext) {
            String sessionId = sessionId(context);
            if (sessionId != null) {
                context.addHighCardinalityKeyValue(KeyValue.of("session.id", sessionId));
            }
        }
        // <<
        // >> The ChatClient call is the invoke agent span
        if (context instanceof ChatClientObservationContext client) {
            // The ChatClient convention sets `gen_ai.operation.name` to `framework` as a metric tag; the span attribute is set here.
            // No `gen_ai.task.output`: a streamed response holds only its first segment, so the service takes the answer
            // from the inference spans.
            context.removeLowCardinalityKeyValue("gen_ai.operation.name");
            context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.operation.name", "invoke_agent"));
            var user = client.getRequest().prompt().getUserMessage();
            if (user != null && user.getText() != null) {
                context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.task.input", user.getText()));
            }
        }
        // <<
        // >> Each model call is an inference span with the messages in the GenAI parts format
        else if (context instanceof ChatModelObservationContext chat) {
            List<Map<String, Object>> input = new ArrayList<>();
            List<Map<String, Object>> system = new ArrayList<>();
            for (Message message : chat.getRequest().getInstructions()) {
                if (message.getMessageType() == MessageType.SYSTEM) {
                    system.add(Map.of("type", "text", "content", message.getText()));
                }
                else {
                    input.add(message(message));
                }
            }
            context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.input.messages", JSON.writeValueAsString(input)));
            context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.system_instructions", JSON.writeValueAsString(system)));
            if (chat.getResponse() != null) {
                List<Map<String, Object>> output = chat.getResponse().getResults().stream()
                    .map(g -> message(g.getOutput())).toList();
                context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.output.messages", JSON.writeValueAsString(output)));
            }
        }
        // <<
        // >> Each tool call is an execute tool span with arguments and result
        else if (context instanceof ToolCallingObservationContext tool) {
            context.addLowCardinalityKeyValue(KeyValue.of("gen_ai.operation.name", "execute_tool"));
            context.addLowCardinalityKeyValue(KeyValue.of("gen_ai.tool.name", tool.getToolDefinition().name()));
            context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.tool.call.arguments", nullToEmpty(tool.getToolCallArguments())));
            context.addHighCardinalityKeyValue(KeyValue.of("gen_ai.tool.call.result", nullToEmpty(tool.getToolCallResult())));
        }
        // <<
        return context;
    }

    /**
     * The session ID of this ChatClient call, or of the ChatClient call that a model or tool call belongs to: the
     * conversation ID (`userId:sessionId`, see `ConversationIdResolver`) without the user ID.
     */
    private static String sessionId(Observation.Context context) {
        for (Observation.ContextView current = context; current != null;
                current = current.getParentObservation() == null ? null : current.getParentObservation().getContextView()) {
            if (current instanceof ChatClientObservationContext client) {
                Object value = client.getRequest().context().get(ChatMemory.CONVERSATION_ID);
                if (value == null) {
                    return null;
                }
                String conversationId = value.toString();
                return conversationId.substring(conversationId.indexOf(':') + 1);
            }
        }
        return null;
    }

    /** A message in the GenAI parts format: text, tool calls, and tool call responses. */
    private static Map<String, Object> message(Message message) {
        List<Map<String, Object>> parts = new ArrayList<>();
        if (message.getText() != null && !message.getText().isEmpty()) {
            parts.add(Map.of("type", "text", "content", message.getText()));
        }
        if (message instanceof AssistantMessage assistant) {
            for (var call : assistant.getToolCalls()) {
                parts.add(Map.of("type", "tool_call", "id", nullToEmpty(call.id()), "name", call.name(), "arguments", nullToEmpty(call.arguments())));
            }
        }
        if (message instanceof ToolResponseMessage tool) {
            for (var response : tool.getResponses()) {
                parts.add(Map.of("type", "tool_call_response", "id", nullToEmpty(response.id()), "response", nullToEmpty(response.responseData())));
            }
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("role", switch (message.getMessageType()) {
            case USER -> "user";
            case ASSISTANT -> "assistant";
            case TOOL -> "tool";
            case SYSTEM -> "system";
        });
        result.put("parts", parts);
        return result;
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }
}
