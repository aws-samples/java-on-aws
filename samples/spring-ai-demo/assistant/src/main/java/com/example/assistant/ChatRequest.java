package com.example.assistant;

public record ChatRequest(String prompt, String fileBase64, String fileName) {
    public boolean hasFile() {
        return fileBase64 != null && !fileBase64.trim().isEmpty();
    }

    public boolean hasPrompt() {
        return prompt != null && !prompt.trim().isEmpty();
    }

    // Static factory method for text-only requests
    public static ChatRequest textOnly(String prompt) {
        return new ChatRequest(prompt, null, null);
    }

    // Static factory method for file requests
    public static ChatRequest withFile(String prompt, String fileBase64, String fileName) {
        return new ChatRequest(prompt, fileBase64, fileName);
    }
}
