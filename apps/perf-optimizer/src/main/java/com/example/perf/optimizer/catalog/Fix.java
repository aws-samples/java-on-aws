package com.example.perf.optimizer.catalog;

import java.util.List;

/**
 * How a finding is fixed and where the artifact lands.
 *
 * @param kind     manifest-patch | dockerfile | source-patch | advice
 * @param template classpath template resource rendered into the artifact (may be null for advice)
 * @param files    repo-relative files the artifact touches (guidance for the apply step)
 */
public record Fix(String kind, String template, List<String> files) {
    public static final String MANIFEST_PATCH = "manifest-patch";
    public static final String DOCKERFILE = "dockerfile";
    public static final String SOURCE_PATCH = "source-patch";
    public static final String ADVICE = "advice";
}
