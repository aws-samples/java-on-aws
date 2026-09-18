package com.example.perf.optimizer.explain;

import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.catalog.Fix;
import com.example.perf.optimizer.facts.Facts;

/**
 * Builds the exact apply command(s) for a finding, deterministically in Java (no
 * model). Namespace/deployment/container come from facts; the ECR repo is a
 * placeholder the engineer fills. After applying, re-run {@code analyze} to see
 * the finding flip to RESOLVED with a measured delta.
 */
final class ApplyCommand {

    private ApplyCommand() {}

    static String forFinding(Finding finding, Facts facts) {
        var w = facts == null ? null : facts.workload();
        String ns = w == null ? "unicorn-store-spring" : w.namespace();
        String dep = w == null ? "unicorn-store-spring" : w.deployment();
        String cont = w == null ? "unicorn-store-spring" : w.container();

        return switch (finding.id()) {
            case "memory-over-provisioned" -> """
                # Edit k8s/deployment.yaml (container resources + JAVA_TOOL_OPTIONS) with the artifact, then:
                kubectl -n %s apply -f k8s/deployment.yaml
                kubectl -n %s rollout restart deploy/%s   # a memory-limit shrink needs a restart
                kubectl -n %s rollout status deploy/%s
                # then re-run analyze to see it RESOLVED with the measured delta"""
                .formatted(ns, ns, dep, ns, dep);
            case "startup-cpu-bound" -> """
                # Follow the numbered steps in the artifact: add the CPU resizePolicy + boot CPU,
                # apply, then resize CPU in place once Ready (0 restarts):
                kubectl -n %s apply -f k8s/deployment.yaml
                # ...then the in-place `kubectl patch --subresource resize` from the artifact"""
                .formatted(ns);
            case "startup-checkpointable" -> """
                # 1) Save the CRaC Dockerfile artifact above as Dockerfile.crac (next to pom.xml)
                #    and apply the UnicornPublisher CRaC Resource hook from the artifact.
                # 2) Build + push the CRaC image (scripts/build.sh resolves ECR + DB args from SSM/Secrets):
                IMG=$(./scripts/build.sh crac)
                # 3) Deploy and watch for a sub-second restore:
                kubectl -n %s set image deploy/%s %s="$IMG"
                kubectl -n %s rollout status deploy/%s
                # expect 'Restored ... in <1 s' in the pod logs; re-run analyze to confirm RESOLVED"""
                .formatted(ns, dep, cont, ns, dep);
            case "blocking-call-in-request-path" -> """
                # Apply the source diff, then rebuild + redeploy the app image:
                IMG=$(./scripts/build.sh latest)
                kubectl -n %s set image deploy/%s %s="$IMG"
                kubectl -n %s rollout restart deploy/%s"""
                .formatted(ns, dep, cont, ns, dep);
            case "hpa-metric-with-sidecar" -> """
                # Edit k8s/hpa.yaml per the artifact, then:
                kubectl -n %s apply -f k8s/hpa.yaml"""
                .formatted(ns);
            default -> finding.fix() != null && Fix.ADVICE.equals(finding.fix().kind())
                ? "# Advice only — no artifact to apply."
                : "# Apply the artifact to the listed files, then re-run analyze.";
        };
    }
}
