package com.example.perf.analyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.net.URI;
import java.nio.charset.StandardCharsets;

/**
 * Thin wrapper over AWS SDK v2 S3Client.
 *
 * Path convention:
 *   perf-platform/
 *     analysis/{platform}/{service}/{target}/{ts}/
 *         request.json
 *         events.md
 *         threaddump.json
 *         analysis.md
 *     profiling/{platform}/{service}/{target}/dump-{jobId}.jfr
 *     profiling/{platform}/{service}/{target}/dump-{jobId}.json  (thread dump)
 */
@Component
public class S3Repository {

    private static final Logger logger = LoggerFactory.getLogger(S3Repository.class);

    private final S3Client s3;
    private final String bucket;

    public S3Repository(S3Client s3Client, @Value("${AWS_S3_BUCKET:}") String bucket) {
        this.s3 = s3Client;
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException(
                "S3 bucket is not configured. Set AWS_S3_BUCKET (from SSM workshop-bucket-name).");
        }
        this.bucket = bucket;
    }

    public String bucketName() { return bucket; }

    public String analysisPrefix(AnalysisService.AnalysisRequest r, String analysisId) {
        return "perf-platform/analysis/%s/%s/%s/%s/".formatted(
            platformSlug(r.platform()), safe(r.service()), safe(r.target()), analysisId);
    }

    public URI analysisObjectUri(String analysisPrefix, String name) {
        return URI.create("s3://%s/%s%s".formatted(bucket, analysisPrefix, name));
    }

    public URI profilingDumpUri(AnalysisService.AnalysisRequest r, String jobId, String ext) {
        var key = "perf-platform/profiling/%s/%s/%s/dump-%s.%s".formatted(
            platformSlug(r.platform()), safe(r.service()), safe(r.target()), jobId, ext);
        return URI.create("s3://%s/%s".formatted(bucket, key));
    }

    public void putBytes(URI s3Uri, byte[] body, String contentType) {
        var key = keyOf(s3Uri);
        s3.putObject(
            PutObjectRequest.builder().bucket(bucket).key(key).contentType(contentType).build(),
            RequestBody.fromBytes(body));
        logger.info("Stored s3://{}/{} ({} bytes, {})", bucket, key, body.length, contentType);
    }

    public void putString(URI s3Uri, String body, String contentType) {
        putBytes(s3Uri, body.getBytes(StandardCharsets.UTF_8), contentType);
    }

    public boolean exists(URI s3Uri) {
        try {
            s3.headObject(HeadObjectRequest.builder().bucket(bucket).key(keyOf(s3Uri)).build());
            return true;
        } catch (NoSuchKeyException _) {
            return false;
        } catch (S3Exception e) {
            if (e.statusCode() == 404) return false;
            throw e;
        }
    }

    public byte[] getBytes(URI s3Uri) {
        ResponseBytes<?> resp = s3.getObjectAsBytes(
            GetObjectRequest.builder().bucket(bucket).key(keyOf(s3Uri)).build());
        return resp.asByteArray();
    }

    private String keyOf(URI s3Uri) {
        var host = s3Uri.getHost();
        if (!bucket.equals(host)) {
            throw new IllegalArgumentException(
                "S3 URI bucket %s != configured %s".formatted(host, bucket));
        }
        var path = s3Uri.getPath();
        return path.startsWith("/") ? path.substring(1) : path;
    }

    private static String platformSlug(AnalysisService.Platform p) {
        return p.name().toLowerCase().replace('_', '-');
    }

    private static String safe(String s) {
        return s == null ? "unknown" : s.replaceAll("[^A-Za-z0-9_.-]", "_");
    }
}
