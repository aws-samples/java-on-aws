package com.amazonaws.springcloudfunctiondemo;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.function.context.FunctionCatalog;
import org.springframework.cloud.function.context.MessageRoutingCallback;
import org.springframework.messaging.MessageHeaders;
import org.springframework.messaging.support.GenericMessage;

import java.util.Map;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
public class MessageCallBackTest {

    @Autowired
    private FunctionCatalog catalog;
    
    @Autowired
    private MessageRoutingCallback customRouter;

    @Test
    public void testCustomRouter() {
        // Create test message
        var unicorn = new com.amazonaws.springcloudfunctiondemo.Unicorn("RouterUnicorn", 2);
        var headers = new MessageHeaders(Map.of("x-routing-key", "unicorn"));
        var message = new GenericMessage<>(unicorn, headers);

        // Use the router to determine the function name
        var functionName = customRouter.routingResult(message);

        // Verify the router returns the expected function name
        assertEquals("helloUnicorn", functionName);

        // Get the function and apply it
        Function<com.amazonaws.springcloudfunctiondemo.Unicorn, String> function = catalog.lookup(Function.class, functionName);
        var result = function.apply(unicorn);

        // Verify result
        assertNotNull(result);
        assertEquals("Hello RouterUnicorn! You are 2 years old!", result);
    }
}
