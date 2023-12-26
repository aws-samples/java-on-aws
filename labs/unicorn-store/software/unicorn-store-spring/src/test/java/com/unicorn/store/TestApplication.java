package com.unicorn.store;

import org.springframework.boot.SpringApplication;

public class TestApplication {
    public static void main(String[] args) {
        SpringApplication
            .from(StoreApplication::main)
            .with(ContainersConfig.class)
            .run(args);
    }
}
