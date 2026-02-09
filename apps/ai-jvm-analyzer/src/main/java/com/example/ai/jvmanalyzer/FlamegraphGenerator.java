package com.example.ai.jvmanalyzer;

import one.convert.Arguments;
import one.convert.JfrToFlame;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Generates flamegraph outputs from JFR data using the official async-profiler
 * jfr-converter library (tools.profiler:jfr-converter).
 */
public class FlamegraphGenerator {

    private static final Logger logger = LoggerFactory.getLogger(FlamegraphGenerator.class);

    /**
     * Converts a JFR file to an HTML flamegraph string.
     * When includePattern is provided (e.g. "*unicorn*"), only matching frames are shown.
     */
    public static String generateHtml(Path jfrFile, String includePattern) throws IOException {
        Path tempHtml = Files.createTempFile("flamegraph-", ".html");
        try {
            if (includePattern != null && !includePattern.isBlank()) {
                var args = new Arguments("--wall", "--inverted",
                    "--include", includePattern,
                    jfrFile.toString(), tempHtml.toString());
                JfrToFlame.convert(jfrFile.toString(), tempHtml.toString(), args);
            } else {
                var args = new Arguments("--wall", "--inverted",
                    jfrFile.toString(), tempHtml.toString());
                JfrToFlame.convert(jfrFile.toString(), tempHtml.toString(), args);
            }

            String html = Files.readString(tempHtml);
            logger.info("Generated flamegraph HTML: {} bytes (include={})", html.length(), includePattern);
            return html;
        } finally {
            Files.deleteIfExists(tempHtml);
        }
    }

    /**
     * Converts a JFR file to collapsed stacks text — one line per unique stack
     * with sample count. Uses async-profiler's own frame attribution logic.
     */
    public static String generateCollapsed(Path jfrFile) throws IOException {
        Path tempCollapsed = Files.createTempFile("collapsed-", ".txt");
        try {
            var args = new Arguments("--wall",
                jfrFile.toString(), tempCollapsed.toString());
            args.output = "collapsed";

            JfrToFlame.convert(jfrFile.toString(), tempCollapsed.toString(), args);

            String collapsed = Files.readString(tempCollapsed);
            logger.info("Generated collapsed stacks: {} bytes", collapsed.length());
            return collapsed;
        } finally {
            Files.deleteIfExists(tempCollapsed);
        }
    }
}
