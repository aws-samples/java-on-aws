package com.amazonaws.springcloudfunctiondemo;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.function.context.MessageRoutingCallback;
import org.springframework.context.annotation.Bean;
import org.springframework.messaging.Message;

import java.util.function.Consumer;
import java.util.function.Function;

@SpringBootApplication
public class SpringCloudFunctionDemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(SpringCloudFunctionDemoApplication.class, args);
    }

    @Bean
    public Function<String, String> lowerCase() {return String::toLowerCase;}

    @Bean
    public Function<String, String> upperCase(){
        return String::toUpperCase;
    }

    @Bean
    public Function<String, String> reverse(){
        return value -> new StringBuilder(value).reverse().toString();
    }

    @Bean
    public Function<com.amazonaws.springcloudfunctiondemo.Unicorn, String> helloUnicorn(){
        return value -> "Hello %s! You are %d years old!".formatted(value.name(), value.age());
    }

    @Bean
    public Consumer<SQSEvent> asyncProcessor(){
        return value -> System.out.printf("Processed %d messages!", value.getRecords().size());
    }

    @Bean
    public Function<String, String> noOpFunction(){
        return value -> "No proper function found!";
    }

    @Bean
    public MessageRoutingCallback customRouter() {
        return new MessageRoutingCallback() {
            @Override
            public String routingResult(Message<?> message) {
                System.out.println("Hello from MessageRoutingCallback");
                var routingKey = message.getHeaders().getOrDefault("x-routing-key", "").toString();
                return switch (routingKey) {
                    case "uppercase" -> "upperCase";
                    case "lowercase" -> "lowerCase";
                    case "reverse" -> "reverse";
                    case "unicorn" -> "helloUnicorn";
                    default -> "noOpFunction";
                };
            }
        };
    }
}
