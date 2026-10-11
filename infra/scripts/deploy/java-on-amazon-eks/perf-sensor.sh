#!/bin/bash
# java-on-amazon-eks runs the java-performance implementation of this step: the two workshops
# share the app, the sensor and the profiler, and one copy keeps a fix in one place. Replace
# this wrapper with an own script when the workshops diverge.
exec bash "$(dirname "${BASH_SOURCE[0]}")/../java-performance/$(basename "${BASH_SOURCE[0]}")" "$@"
