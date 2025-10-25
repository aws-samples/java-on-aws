package com.example.ai.agent.model;

import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.MediaTypeFactory;
import org.springframework.util.MimeType;
import org.springframework.util.MimeTypeUtils;

import java.util.Base64;

public record ChatRequest(String prompt, String fileBase64, String fileName) {
    public boolean hasFile() {
        return fileBase64 != null && !fileBase64.trim().isEmpty();
    }

    public boolean hasPrompt() {
        return prompt != null && !prompt.trim().isEmpty();
    }

    public FileResource buildFileResource() {
        if (!hasFile()) {
            throw new IllegalStateException("Cannot build file resource without file data");
        }

        MimeType mimeType = determineMimeType();
        byte[] fileData = Base64.getDecoder().decode(fileBase64);
        ByteArrayResource resource = new ByteArrayResource(fileData);
        return new FileResource(mimeType, resource);
    }

    public String getEffectivePrompt(String defaultPrompt) {
        return hasPrompt() ? prompt : defaultPrompt;
    }

    private MimeType determineMimeType() {
        if (fileName != null && !fileName.trim().isEmpty()) {
            MediaType mediaType = MediaTypeFactory.getMediaType(fileName)
                    .orElse(MediaType.APPLICATION_OCTET_STREAM);
            return new MimeType(mediaType.getType(), mediaType.getSubtype());
        }
        return MimeTypeUtils.APPLICATION_OCTET_STREAM;
    }

    public static ChatRequest textOnly(String prompt) {
        return new ChatRequest(prompt, null, null);
    }

    public static ChatRequest withFile(String prompt, String fileBase64, String fileName) {
        return new ChatRequest(prompt, fileBase64, fileName);
    }

    public record FileResource(MimeType mimeType, ByteArrayResource resource) {}
}
