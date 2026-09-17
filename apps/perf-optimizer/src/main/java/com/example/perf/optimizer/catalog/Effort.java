package com.example.perf.optimizer.catalog;

/**
 * Fix effort, which also encodes the ladder of stages: LOW = manifest change,
 * MEDIUM = image rebuild (AOT/CRaC), HIGH = source change. {@link #rank} orders
 * ranking (lower effort ranks higher for equal severity).
 */
public enum Effort {
    LOW(1), MEDIUM(2), HIGH(3);

    private final int rank;

    Effort(int rank) {
        this.rank = rank;
    }

    public int rank() {
        return rank;
    }
}
