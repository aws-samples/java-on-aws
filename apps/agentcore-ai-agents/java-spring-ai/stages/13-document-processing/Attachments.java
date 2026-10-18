package com.example.agent;

import java.util.Base64;
import java.util.UUID;

import org.springframework.ai.bedrock.converse.api.BedrockMediaFormat;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.content.Media;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.MediaTypeFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.MimeType;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;

/**
 * The user's message: the prompt, plus the attached file as media for the model. The file is also uploaded to S3,
 * and its URI is added to the prompt, so tools such as extractReceipt can read it.
 */
@Component
public class Attachments {

    private final S3Client s3 = S3Client.create();
    private final String bucket;

    public Attachments(@Value("${app.artifacts.bucket}") String bucket) {
        this.bucket = bucket;
    }

    public void message(ChatClient.PromptUserSpec user, String prompt, String fileName, String fileBase64) {
        // >> The UI sends the file as base64 with its name; without a file, the prompt stays plain text
        if (fileName == null || fileName.isEmpty() || fileBase64 == null || fileBase64.isEmpty()) {
            user.text(prompt);
            return;
        }
        // <<
        byte[] data = Base64.getDecoder().decode(fileBase64);
        // >> Upload under `artifacts/uploads/` (expires after one day) and add the S3 URI to the prompt
        String key = "artifacts/uploads/" + UUID.randomUUID() + "/" + fileName;
        s3.putObject(b -> b.bucket(bucket).key(key), RequestBody.fromBytes(data));
        user.text(prompt + "\n[Attached file: " + fileName + ", S3 URI: s3://" + bucket + "/" + key + "]");
        // <<
        // >> Spring AI media: the Bedrock Converse model sends images and documents to the model as content blocks
        MimeType mimeType = MediaTypeFactory.getMediaType(fileName).orElse(MediaType.APPLICATION_OCTET_STREAM);
        if (BedrockMediaFormat.isSupportedImageFormat(mimeType) || BedrockMediaFormat.isSupportedDocumentFormat(mimeType)) {
            user.media(Media.builder().mimeType(mimeType).data(data).name(fileName).build());
        }
        // <<
    }
}
