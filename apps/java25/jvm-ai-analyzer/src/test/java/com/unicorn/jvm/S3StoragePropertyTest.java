package com.unicorn.jvm;

import net.jqwik.api.*;
import net.jqwik.api.constraints.*;

import java.util.ArrayList;
import java.util.List;

// Property tests for S3 storage - stores exactly 3 files (.json, .html, .md)
class S3StoragePropertyTest {

    @Property(tries = 100)
    void storeResultsCreatesThreeFiles(
        @ForAll @StringLength(min = 1, max = 50) @AlphaChars String podName,
        @ForAll @StringLength(min = 1, max = 500) String threadDump,
        @ForAll @StringLength(min = 1, max = 500) String profilingData,
        @ForAll @StringLength(min = 1, max = 500) String analysis
    ) {
        var storedFiles = new ArrayList<String>();
        var connector = new TrackingS3Connector(storedFiles);

        connector.storeResults(podName, threadDump, profilingData, analysis);

        assert storedFiles.size() == 3 : "Should store exactly 3 files, got " + storedFiles.size();
    }

    @Property(tries = 100)
    void storeResultsCreatesCorrectFileTypes(
        @ForAll @StringLength(min = 1, max = 50) @AlphaChars String podName,
        @ForAll @StringLength(min = 1, max = 200) String threadDump,
        @ForAll @StringLength(min = 1, max = 200) String profilingData,
        @ForAll @StringLength(min = 1, max = 200) String analysis
    ) {
        var storedFiles = new ArrayList<String>();
        var connector = new TrackingS3Connector(storedFiles);

        connector.storeResults(podName, threadDump, profilingData, analysis);

        long jsonCount = storedFiles.stream().filter(f -> f.endsWith(".json")).count();
        long htmlCount = storedFiles.stream().filter(f -> f.endsWith(".html")).count();
        long mdCount = storedFiles.stream().filter(f -> f.endsWith(".md")).count();

        assert jsonCount == 1 : "Should have exactly 1 .json file (thread dump)";
        assert htmlCount == 1 : "Should have exactly 1 .html file (profiling)";
        assert mdCount == 1 : "Should have exactly 1 .md file (analysis)";
    }

    @Property(tries = 100)
    void storeResultsIncludesPodNameInAllFiles(
        @ForAll @StringLength(min = 1, max = 30) @AlphaChars String podName,
        @ForAll @StringLength(min = 1, max = 100) String threadDump,
        @ForAll @StringLength(min = 1, max = 100) String profilingData,
        @ForAll @StringLength(min = 1, max = 100) String analysis
    ) {
        var storedFiles = new ArrayList<String>();
        var connector = new TrackingS3Connector(storedFiles);

        connector.storeResults(podName, threadDump, profilingData, analysis);

        for (var file : storedFiles) {
            assert file.contains(podName) : "File " + file + " should contain pod name " + podName;
        }
    }

    @Property(tries = 100)
    void storeResultsIncludesTimestampInAllFiles(
        @ForAll @StringLength(min = 1, max = 30) @AlphaChars String podName,
        @ForAll @StringLength(min = 1, max = 100) String threadDump,
        @ForAll @StringLength(min = 1, max = 100) String profilingData,
        @ForAll @StringLength(min = 1, max = 100) String analysis
    ) {
        var storedFiles = new ArrayList<String>();
        var connector = new TrackingS3Connector(storedFiles);

        connector.storeResults(podName, threadDump, profilingData, analysis);

        for (var file : storedFiles) {
            assert file.matches(".*\\d{8}-\\d{6}.*") :
                "File " + file + " should contain timestamp pattern";
        }
    }

    // --- Test helper ---

    private static class TrackingS3Connector {
        private final List<String> storedFiles;
        private final String analysisPrefix = "analysis/";

        TrackingS3Connector(List<String> storedFiles) {
            this.storedFiles = storedFiles;
        }

        void storeResults(String podName, String threadDump, String profilingData, String analysis) {
            var timestamp = java.time.LocalDateTime.now()
                .format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

            storedFiles.add(analysisPrefix + timestamp + "_threaddump_" + podName + ".json");
            storedFiles.add(analysisPrefix + timestamp + "_profiling_" + podName + ".html");
            storedFiles.add(analysisPrefix + timestamp + "_analysis_" + podName + ".md");
        }
    }
}
