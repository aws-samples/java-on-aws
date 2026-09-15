package com.example.perf.optimizer;

import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

/**
 * perf-optimizer — a Bedrock-backed optimization agent exposed over MCP.
 *
 * Separate app from perf-analyzer (which powers the analysis labs) so those
 * stay intact. Thin-slice POC: exposes ONE MCP tool, {@code optimizeService},
 * that reads live Pyroscope signals and returns a grounded right-size / GC /
 * startup recommendation. Claude Code on the dev EC2 is the MCP client and
 * implements the recommendation.
 */
@SpringBootApplication
public class OptimizerApplication {

    public static void main(String[] args) {
        SpringApplication.run(OptimizerApplication.class, args);
    }

    @Bean
    S3Client s3Client(@Value("${AWS_REGION:us-east-1}") String region) {
        return S3Client.builder().region(Region.of(region)).build();
    }

    /** Register OptimizerTools' @Tool methods as MCP server tools. */
    @Bean
    ToolCallbackProvider optimizerToolCallbacks(OptimizerTools optimizerTools) {
        return MethodToolCallbackProvider.builder()
            .toolObjects(optimizerTools)
            .build();
    }
}
