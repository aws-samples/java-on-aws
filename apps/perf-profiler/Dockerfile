# perf-profiler — privilege-free JVM profiler sidecar (Amazon Corretto 25 +
# async-profiler, baked). Attaches across a shared PID namespace with only
# SYS_PTRACE (no privileged, no hostPID) and pushes JFR to Pyroscope.
#
# Everything is baked at build time — there is no runtime download — so the
# sidecar starts fast and works in air-gapped clusters. Linux x86-64 (matches
# the workshop's amd64 nodes); bump ASYNC_PROFILER_VERSION to upgrade.
FROM public.ecr.aws/docker/library/amazoncorretto:25

ARG ASYNC_PROFILER_VERSION=4.4
ARG TARGETARCH=x64

# tar/gzip are only needed to unpack async-profiler at build time. curl (curl-minimal),
# bash, sed, and coreutils (stat/ls) ship in the Corretto AL2023 base and are used
# by the runtime loop.
RUN yum install -y tar gzip && yum clean all

# Bake async-profiler into the image (no runtime GitHub fetch).
RUN curl -sSL -o /tmp/ap.tgz \
      "https://github.com/async-profiler/async-profiler/releases/download/v${ASYNC_PROFILER_VERSION}/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${TARGETARCH}.tar.gz" \
  && mkdir -p /opt/async-profiler \
  && tar -xz -C /opt/async-profiler --strip-components=1 -f /tmp/ap.tgz \
  && rm -f /tmp/ap.tgz \
  && test -f /opt/async-profiler/lib/libasyncProfiler.so

COPY profile-loop.sh /usr/local/bin/profile-loop.sh
RUN chmod +x /usr/local/bin/profile-loop.sh

ENV AP_HOME=/opt/async-profiler
ENTRYPOINT ["/usr/local/bin/profile-loop.sh"]
