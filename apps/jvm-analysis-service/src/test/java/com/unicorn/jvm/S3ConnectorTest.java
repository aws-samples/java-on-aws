package com.unicorn.jvm;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class S3ConnectorTest {

    @Mock
    private S3Client s3Client;

    private S3Connector s3Connector;

    @BeforeEach
    void setUp() {
        s3Connector = new S3Connector();
        ReflectionTestUtils.setField(s3Connector, "s3Client", s3Client);
        ReflectionTestUtils.setField(s3Connector, "s3Bucket", "test-bucket");
        ReflectionTestUtils.setField(s3Connector, "s3PrefixAnalysis", "analysis/");
        ReflectionTestUtils.setField(s3Connector, "s3PrefixProfiling", "profiling/");
    }

    @Test
    void getLatestProfilingData_shouldReturnDataWhenFileExists() {
        String taskPodId = "test-pod";
        String fileContent = "java/lang/Thread.run;java/util/concurrent/locks/LockSupport.parkNanos 100";

        S3Object s3Object = S3Object.builder()
                .key("profiling/test-pod/20250924/test-file.txt")
                .lastModified(Instant.now())
                .build();

        ListObjectsV2Response listResponse = ListObjectsV2Response.builder()
                .contents(List.of(s3Object))
                .build();

        GetObjectResponse getResponse = GetObjectResponse.builder().build();

        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class))).thenReturn(listResponse);
        when(s3Client.getObjectAsBytes(any(GetObjectRequest.class)))
                .thenReturn(ResponseBytes.fromByteArray(getResponse, fileContent.getBytes()));

        String result = s3Connector.getLatestProfilingData(taskPodId);

        assertNotNull(result);
        assertEquals(fileContent, result);
    }

    @Test
    void getLatestProfilingData_shouldReturnNullWhenNoFilesFound() {
        String taskPodId = "test-pod";

        ListObjectsV2Response listResponse = ListObjectsV2Response.builder()
                .contents(List.of())
                .build();

        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class))).thenReturn(listResponse);

        String result = s3Connector.getLatestProfilingData(taskPodId);

        assertNull(result);
    }

    @Test
    void storeProfilingData_shouldCallS3PutObject() {
        String taskPodId = "test-pod";
        String content = "profiling content";
        String timestamp = "20250924-120000";

        s3Connector.storeProfilingData(taskPodId, content, timestamp);

        verify(s3Client, times(1)).putObject(any(PutObjectRequest.class), any(RequestBody.class));
    }

    @Test
    void storeFlameGraph_shouldCallS3PutObject() {
        String taskPodId = "test-pod";
        String flamegraph = "<html>flamegraph</html>";
        String timestamp = "20250924-120000";

        s3Connector.storeFlameGraph(taskPodId, flamegraph, timestamp);

        verify(s3Client, times(1)).putObject(any(PutObjectRequest.class), any(RequestBody.class));
    }

    @Test
    void storeResults_shouldStoreThreadDumpAndAnalysis() {
        String taskPodId = "test-pod";
        String threadDump = "thread dump content";
        String analysis = "analysis content";

        s3Connector.storeResults(taskPodId, threadDump, analysis);

        verify(s3Client, times(2)).putObject(any(PutObjectRequest.class), any(RequestBody.class));
    }

    @Test
    void extractTimestampFromFileName_shouldExtractCorrectly() {
        String fullKey = "profiling/test-pod/20250924/20250924-120000.txt";

        String result = s3Connector.extractTimestampFromFileName(fullKey);

        assertEquals("20250924-120000", result);
    }
}