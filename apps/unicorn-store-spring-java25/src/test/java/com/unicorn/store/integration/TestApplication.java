package com.unicorn.store.integration;

import org.springframework.boot.SpringApplication;
import com.unicorn.store.StoreApplication;

public class TestApplication {
    public static void main(String[] args) {
        SpringApplication
            .from(StoreApplication::main)
            .run(args);
    }
}
