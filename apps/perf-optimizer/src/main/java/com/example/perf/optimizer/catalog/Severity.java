package com.example.perf.optimizer.catalog;

/** Finding severity; {@link #rank} orders ranking (higher = more severe). */
public enum Severity {
    LOW(1), MEDIUM(2), HIGH(3), CRITICAL(4);

    private final int rank;

    Severity(int rank) {
        this.rank = rank;
    }

    public int rank() {
        return rank;
    }
}
