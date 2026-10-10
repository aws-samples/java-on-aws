package com.example.perf.sensor.checklist;

import dev.cel.bundle.Cel;
import dev.cel.bundle.CelFactory;
import dev.cel.common.CelFunctionDecl;
import dev.cel.common.CelOptions;
import dev.cel.common.CelOverloadDecl;
import dev.cel.common.types.SimpleType;
import dev.cel.common.values.NullValue;
import dev.cel.parser.CelStandardMacro;
import dev.cel.runtime.CelFunctionBinding;
import dev.cel.runtime.CelRuntime;
import org.yaml.snakeyaml.Yaml;

import java.io.InputStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Evaluates the checklist rules ({@code checklist-rules.yaml}) over a facts map. Generic: it
 * knows the rule format (requires, underLoad, values, pass, evidence), not any practice. The
 * expressions are CEL, compiled once at construction so a broken rules file fails at startup.
 * CEL has no side effects and no I/O, so the rules can only read the facts they are given.
 */
public class ChecklistEngine {

    public enum Verdict { PASS, FAIL, UNKNOWN }

    public record Item(int id, String practice, Verdict verdict, String evidence) {
        public String icon() {
            return switch (verdict) {
                case PASS -> "✅";
                case FAIL -> "❌";
                case UNKNOWN -> "🟡";
            };
        }
    }

    record Rule(int id, String practice, boolean underLoad, List<String> requires, String unknown,
                Map<String, CelRuntime.Program> values, CelRuntime.Program pass, String evidence) {}

    private static final List<String> FACT_VARS =
        List.of("workload", "runtime", "jfr", "profile", "window", "threads", "blocking");
    private static final Pattern PLACEHOLDER = Pattern.compile("\\{(\\w+)(?::(\\d+))?}");

    private final List<Rule> rules;
    private final double minRequestRate;

    public ChecklistEngine(InputStream rulesYaml) {
        Map<String, Object> doc = new Yaml().load(rulesYaml);
        this.minRequestRate = ((Number) doc.getOrDefault("minRequestRate", 1.0)).doubleValue();
        var parsed = new ArrayList<Rule>();
        for (Object o : (List<?>) doc.get("items")) {
            parsed.add(compile(asMap(o)));
        }
        this.rules = List.copyOf(parsed);
    }

    public int size() {
        return rules.size();
    }

    /** Request rate (rps, over the window) at which the window counts as under load. */
    public double minRequestRate() {
        return minRequestRate;
    }

    /** Evaluate every rule over {@code facts}: keys are the fact variables, values plain maps. */
    public List<Item> evaluate(Map<String, Object> facts) {
        var vars = new HashMap<String, Object>();
        for (String v : FACT_VARS) {
            Object f = facts.get(v);
            vars.put(v, f == null ? Map.of() : f);
        }
        Double rate = asDouble(lookup(vars, "window.requestRatePerSec"));
        boolean underLoad = rate != null && rate >= minRequestRate;
        return rules.stream().map(r -> evaluate(r, vars, underLoad)).toList();
    }

    private Item evaluate(Rule r, Map<String, Object> vars, boolean underLoad) {
        if (r.underLoad() && !underLoad) {
            return new Item(r.id(), r.practice(), Verdict.UNKNOWN, "no load in window");
        }
        var missing = r.requires().stream()
            .filter(path -> java.util.Arrays.stream(path.split("\\|")).allMatch(p -> lookup(vars, p) == null))
            .toList();
        if (!missing.isEmpty()) {
            String why = r.unknown() != null ? r.unknown()
                : String.join(", ", missing.stream().map(p -> p.replace("|", " / ") + " null").toList());
            return new Item(r.id(), r.practice(), Verdict.UNKNOWN, why);
        }
        var activation = new HashMap<>(vars);
        var computed = new LinkedHashMap<String, Object>();
        try {
            for (var e : r.values().entrySet()) {
                Object v = e.getValue().eval(activation);
                activation.put(e.getKey(), v);
                computed.put(e.getKey(), v);
            }
            boolean pass = Boolean.TRUE.equals(r.pass().eval(activation));
            return new Item(r.id(), r.practice(), pass ? Verdict.PASS : Verdict.FAIL, render(r.evidence(), computed));
        } catch (Exception e) {
            return new Item(r.id(), r.practice(), Verdict.UNKNOWN, "rule error: " + e.getMessage());
        }
    }

    // --- rendering ----------------------------------------------------------------

    /** "Score: N/12", a blank line, then the markdown table, icon first. */
    public static String markdown(List<Item> items) {
        var sb = new StringBuilder("Score: ").append(score(items)).append('/').append(items.size()).append("\n\n");
        sb.append("| | # | Practice | Evidence |\n|---|---|---|---|\n");
        for (var i : items) {
            sb.append("| ").append(i.icon()).append(" | ").append(i.id()).append(" | ").append(i.practice())
                .append(" | ").append(i.evidence().replace("|", "\\|")).append(" |\n");
        }
        return sb.toString();
    }

    /** The same table as aligned plain text, for a terminal. */
    public static String text(List<Item> items) {
        int w = items.stream().mapToInt(i -> i.practice().length()).max().orElse(10);
        var sb = new StringBuilder("Score: ").append(score(items)).append('/').append(items.size()).append("\n\n");
        for (var i : items) {
            sb.append(i.icon()).append(' ').append(String.format("%2d", i.id())).append("  ")
                .append(String.format("%-" + w + "s", i.practice())).append("  ").append(i.evidence()).append('\n');
        }
        return sb.toString();
    }

    public static long score(List<Item> items) {
        return items.stream().filter(i -> i.verdict() == Verdict.PASS).count();
    }

    static String render(String template, Map<String, Object> values) {
        Matcher m = PLACEHOLDER.matcher(template);
        var sb = new StringBuilder();
        while (m.find()) {
            Object v = values.get(m.group(1));
            Integer decimals = m.group(2) == null ? null : Integer.parseInt(m.group(2));
            m.appendReplacement(sb, Matcher.quoteReplacement(format(v, decimals)));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    /** Whole numbers without decimals; others rounded (default 4 places), trailing zeros dropped. */
    static String format(Object v, Integer decimals) {
        if (v == null || v instanceof NullValue) {
            return "n/a";
        }
        if (v instanceof Number n) {
            double d = n.doubleValue();
            if (d == Math.rint(d) && Math.abs(d) < 1e15) {
                return String.valueOf((long) d);
            }
            return BigDecimal.valueOf(d).setScale(decimals == null ? 4 : decimals, RoundingMode.HALF_UP)
                .stripTrailingZeros().toPlainString();
        }
        return String.valueOf(v);
    }

    // --- compilation --------------------------------------------------------------

    private static Rule compile(Map<String, Object> m) {
        int id = ((Number) m.get("id")).intValue();
        var valueExprs = asMap(m.getOrDefault("values", Map.of()));
        Cel cel = cel(valueExprs.keySet());
        var values = new LinkedHashMap<String, CelRuntime.Program>();
        valueExprs.forEach((k, v) -> values.put(k, program(cel, id, String.valueOf(v))));
        @SuppressWarnings("unchecked")
        List<String> requires = (List<String>) m.getOrDefault("requires", List.of());
        return new Rule(id, (String) m.get("practice"), Boolean.TRUE.equals(m.get("underLoad")),
            List.copyOf(requires), (String) m.get("unknown"), values,
            program(cel, id, String.valueOf(m.get("pass"))), (String) m.get("evidence"));
    }

    private static CelRuntime.Program program(Cel cel, int id, String expr) {
        try {
            return cel.createProgram(cel.compile(expr).getAst());
        } catch (Exception e) {
            throw new IllegalStateException("checklist rule " + id + ": cannot compile '" + expr + "': " + e.getMessage(), e);
        }
    }

    /** A CEL environment with the fact variables, the rule's value names and two math helpers. */
    private static Cel cel(Iterable<String> valueNames) {
        var b = CelFactory.standardCelBuilder()
            .setStandardMacros(CelStandardMacro.STANDARD_MACROS)
            .setOptions(CelOptions.current().enableHeterogeneousNumericComparisons(true).build())
            .addFunctionDeclarations(
                CelFunctionDecl.newFunctionDeclaration("ceil",
                    CelOverloadDecl.newGlobalOverload("ceil_double", SimpleType.DOUBLE, SimpleType.DOUBLE)),
                CelFunctionDecl.newFunctionDeclaration("roundUp",
                    CelOverloadDecl.newGlobalOverload("roundUp_double_double", SimpleType.DOUBLE,
                        SimpleType.DOUBLE, SimpleType.DOUBLE)))
            .addFunctionBindings(
                CelFunctionBinding.from("ceil_double", Double.class, Math::ceil),
                CelFunctionBinding.from("roundUp_double_double", Double.class, Double.class, ChecklistEngine::roundUp));
        for (String v : FACT_VARS) {
            b.addVar(v, SimpleType.DYN);
        }
        for (String v : valueNames) {
            b.addVar(v, SimpleType.DYN);
        }
        return b.build();
    }

    /** Round x up to a multiple of step, without float noise (roundUp(0.3275, 0.05) = 0.35). */
    static double roundUp(double x, double step) {
        double r = Math.ceil(x / step - 1e-9) * step;
        return Math.round(r * 1e6) / 1e6;
    }

    // --- facts access -------------------------------------------------------------

    static Object lookup(Map<String, Object> vars, String path) {
        Object cur = vars;
        for (String part : path.split("\\.")) {
            if (!(cur instanceof Map<?, ?> map)) {
                return null;
            }
            cur = map.get(part);
        }
        return cur;
    }

    private static Double asDouble(Object o) {
        return o instanceof Number n ? n.doubleValue() : null;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object o) {
        return (Map<String, Object>) o;
    }
}
