package com.example.perf.sensor.facts;

/** A single profiled leaf function with its self-time share of the profile (percent). */
public record Frame(String name, double selfPct) {}
