package com.example.agent;

public record InvocationRequest(String prompt, String fileBase64, String fileName) {
	public boolean hasFile() {
		return fileBase64 != null && !fileBase64.isEmpty() && fileName != null && !fileName.isEmpty();
	}
}
