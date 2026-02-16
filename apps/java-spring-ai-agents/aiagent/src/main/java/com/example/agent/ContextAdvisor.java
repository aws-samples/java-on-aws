package com.example.agent;

import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.client.ChatClientResponse;
import org.springframework.ai.chat.client.advisor.api.AdvisorChain;
import org.springframework.ai.chat.client.advisor.api.BaseAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.stereotype.Component;

@Component
class ContextAdvisor implements BaseAdvisor {

    @Override
    public ChatClientRequest before(ChatClientRequest request, AdvisorChain advisorChain) {
        Prompt original = request.prompt();
        String timestamp = ZonedDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
        String conversationId = (String) request.context().get(ChatMemory.CONVERSATION_ID);
        String userId = conversationId != null ? conversationId.split(":")[0] : "unknown";

        List<Message> messages = new ArrayList<>(original.getInstructions());
        UserMessage userMsg = original.getUserMessage();
        if (userMsg != null) {
            messages.remove(userMsg);
            messages.add(new UserMessage("[Current date and time: " + timestamp + "]"));
            messages.add(new UserMessage("[UserId: " + userId + "]\n" + userMsg.getText()));
        }

        Prompt augmented = new Prompt(messages, original.getOptions());
        return request.mutate().prompt(augmented).build();
    }

    @Override
    public ChatClientResponse after(ChatClientResponse response, AdvisorChain advisorChain) {
        return response;
    }

	@Override
    public int getOrder() {
        return 0;
    }
}
