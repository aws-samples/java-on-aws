package com.example.perf.optimizer.facts;

/** A single profiled leaf function with its self-time share of the profile. */
public record Frame(String name, double selfPct) {}
