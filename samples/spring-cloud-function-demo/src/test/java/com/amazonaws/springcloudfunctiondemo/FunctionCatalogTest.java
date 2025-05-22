package com.amazonaws.springcloudfunctiondemo;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.function.context.FunctionCatalog;
import org.springframework.cloud.function.context.config.RoutingFunction;

import java.util.List;
import java.util.function.Consumer;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest
public class FunctionCatalogTest {

    @Autowired
    private FunctionCatalog functionCatalog;

    @Test
    public void testFunction() {
        Function<String, String> functionDefinition = functionCatalog.lookup("upperCase");
        var result = functionDefinition.apply("spring");

        assertEquals("SPRING", result);
    }

    //Routing Function Test - Defined in application.properties
    //spring.cloud.function.definition=reverse
    @Test
    public void testFunctionRouting() {
        Function<String, String> functionDefinition = functionCatalog.lookup(RoutingFunction.FUNCTION_NAME);
        var result = functionDefinition.apply("spring");

        assertEquals("gnirps", result);
    }

    @Test
    public void testHandleSQSMessages() {
        // Get function from catalog
        Consumer<SQSEvent> function = functionCatalog.lookup(Function.class, "asyncProcessor");
        assertNotNull(function);

        var sqsMessage = new SQSEvent();
        sqsMessage.setRecords(List.of(new SQSEvent.SQSMessage()));

        // Create test data and invoke function
        function.accept(sqsMessage);
    }
}
