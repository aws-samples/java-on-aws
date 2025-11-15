package com.example.ai.agent;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
class WebClientConfiguration {

    @Bean
    WebClient.Builder apiKeyInjectingWebClientBuilder(@Value("${agent.api.key}") String apiKey) {
//        return WebClient.builder().apply(builder -> builder
//                .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + "eyJraWQiOiJ0ZTA3MVdlRjV1MWNuekhqUVJuenh5MXRubFRERHJjQ3lwdmtPT0ppUGlrPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI5NDU4YzQzOC02MDAxLTcwZmUtZTg2MS1jZTM1NDYwYzUyZTMiLCJjdXN0b206dGVuYW50VGllciI6ImJhc2ljIiwiaXNzIjoiaHR0cHM6XC9cL2NvZ25pdG8taWRwLnVzLWVhc3QtMS5hbWF6b25hd3MuY29tXC91cy1lYXN0LTFfMHF4TlZvODMzIiwidmVyc2lvbiI6MiwiY2xpZW50X2lkIjoiNjdyajliMzU4dTNxZXA1czNwM2UxdDZtMGciLCJvcmlnaW5fanRpIjoiNjUwYTI1MjMtNTBkNy00N2ZhLWFmNGUtNzllZjlkOWQ1ZGJmIiwiY3VzdG9tOnRlbmFudElkIjoiVVNFUl9NRVRYMTROSF9BQkxBSVIiLCJldmVudF9pZCI6IjJlYmI2YTJlLTY2NjUtNDcxZS1hOGUyLTJkMDU0NzZjMjM1NSIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJhdXRoX3RpbWUiOjE3NTYzOTIzMDEsImV4cCI6MTc1NjM5NTkwMSwiaWF0IjoxNzU2MzkyMzAxLCJqdGkiOiIzMjA0ODdmMC1lNzJhLTRkYTMtODZmYS1jMTFjOWM3YzdiYTkiLCJ1c2VybmFtZSI6Im1jcC11c2VyMSJ9.R-lnzge2UIEtzf-QXOgxfnfACB5M13_njsHwnrhC7naqGIeM_cMwgahb5NMB8QUJKHWk5I9HvIZ3_ZfPG84nhKpZVSYO_RqrChvFJbsa4-3wiHGGfhT6Y4RhjNHBzHIz22o3IubiZv5SPxa-OncTJpJLCR8HOJGCOUJhJ5tdrcnCoh7hzcswRHNNU4mF6nwbPLekSiMWKG1chx5I6lh6XBQPPdrjPt-pU2eSDY5aC75WOkN-0JnMCRoaao3I2oBnjghpEThTKXtyrLMaeNzhPrSF5FwE5LHQMYwW5fTXK8iuq2OD_0a4LDLPlP2kWnJKxnnl_TSRrDsCg-POmn0l4w")
//        );
        return WebClient.builder().apply(builder -> builder
                .defaultHeader("X-API-KEY", apiKey)
        );
    }
}
