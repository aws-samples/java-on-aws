package com.example.perf.optimizer.catalog;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads the finding catalog from a YAML resource ({@code catalog/findings.yaml})
 * into typed {@link CatalogEntry} records. Order in the file is preserved and is
 * the evaluation order; the ranking comparator gives the final display order.
 */
@Component
public class Catalog {

    public static final String DEFAULT_RESOURCE = "catalog/findings.yaml";

    private final List<CatalogEntry> entries;

    public Catalog() {
        this(DEFAULT_RESOURCE);
    }

    public Catalog(String resourcePath) {
        this.entries = load(resourcePath);
    }

    public List<CatalogEntry> entries() {
        return entries;
    }

    @SuppressWarnings("unchecked")
    private static List<CatalogEntry> load(String resourcePath) {
        try (InputStream in = new ClassPathResource(resourcePath).getInputStream()) {
            List<Map<String, Object>> raw = new Yaml().load(in);
            if (raw == null) {
                return List.of();
            }
            var out = new ArrayList<CatalogEntry>(raw.size());
            for (var m : raw) {
                out.add(toEntry(m));
            }
            return List.copyOf(out);
        } catch (IOException e) {
            throw new IllegalStateException("Cannot load catalog " + resourcePath, e);
        }
    }

    @SuppressWarnings("unchecked")
    private static CatalogEntry toEntry(Map<String, Object> m) {
        Map<String, Object> fixMap = (Map<String, Object>) m.get("fix");
        Fix fix = fixMap == null ? null : new Fix(
            str(fixMap.get("kind")),
            str(fixMap.get("template")),
            strList(fixMap.get("files")));
        return new CatalogEntry(
            str(m.get("id")),
            str(m.get("title")),
            Severity.valueOf(str(m.get("severity")).toUpperCase()),
            Effort.valueOf(str(m.get("effort")).toUpperCase()),
            Boolean.TRUE.equals(m.get("guard")),
            str(m.get("detector")),
            strList(m.get("requires")),
            strList(m.get("prereqs")),
            str(m.get("reason")),
            strMap(m.get("compute")),
            strList(m.get("evidence")),
            str(m.get("gain")),
            fix,
            str(m.get("kb")),
            str(m.get("learnMore")));
    }

    private static String str(Object o) {
        return o == null ? null : o.toString();
    }

    @SuppressWarnings("unchecked")
    private static List<String> strList(Object o) {
        if (!(o instanceof List<?> l)) {
            return List.of();
        }
        var out = new ArrayList<String>(l.size());
        for (var e : l) {
            out.add(String.valueOf(e));
        }
        return List.copyOf(out);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, String> strMap(Object o) {
        if (!(o instanceof Map<?, ?> m)) {
            return Map.of();
        }
        var out = new LinkedHashMap<String, String>();
        for (var e : ((Map<String, Object>) m).entrySet()) {
            out.put(e.getKey(), String.valueOf(e.getValue()));
        }
        return out;
    }
}
