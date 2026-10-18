package com.example.agent;

import java.time.Duration;
import java.util.UUID;

import jakarta.annotation.PreDestroy;
import org.springaicommunity.agentcore.artifacts.GeneratedFile;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

/**
 * Uploads generated files (screenshots, charts) to S3 and returns short presigned links.
 * Adapted from java-agent-composer S3ArtifactStreamCustomizer.
 */
@Component
public class ArtifactLinks {

    private final S3Client s3 = S3Client.create();
    private final S3Presigner presigner = S3Presigner.create();
    private final String bucket;

    // >> Artifacts bucket from `application.properties`; objects expire after one day (bucket lifecycle rule)
    public ArtifactLinks(@Value("${app.artifacts.bucket}") String bucket) {
    // <<
        this.bucket = bucket;
    }

    @PreDestroy
    public void close() {
        s3.close();
        presigner.close();
    }

    public String link(GeneratedFile file) {
        // >> Upload the file under `artifacts/` with its content type
        String key = "artifacts/" + UUID.randomUUID() + "/" + file.name();
        s3.putObject(
            PutObjectRequest.builder().bucket(bucket).key(key).contentType(file.mimeType()).build(),
            RequestBody.fromBytes(file.data()));
        // <<
        // >> Return a presigned GET link that is valid for one hour
        return presigner.presignGetObject(GetObjectPresignRequest.builder()
                .getObjectRequest(b -> b.bucket(bucket).key(key))
                .signatureDuration(Duration.ofHours(1))
                .build())
            .url().toString();
        // <<
    }
}
