# perf-profiler — privilege-free JVM profiler sidecar (Amazon Corretto 25 +
# async-profiler, baked). Attaches across a shared PID namespace as the app's UID
# with only SYS_PTRACE added (no root, no privileged, no hostPID) and pushes JFR
# to Pyroscope.
#
# Everything is baked at build time — there is no runtime download — so the
# sidecar starts fast and works in air-gapped clusters. Linux x86-64 (matches
# the workshop's amd64 nodes); to upgrade, bump ASYNC_PROFILER_VERSION AND the
# matching ASYNC_PROFILER_SHA256 (from the release's checksums).
FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023

ARG ASYNC_PROFILER_VERSION=4.4
ARG TARGETARCH=x64
# sha256 of async-profiler-4.4-linux-x64.tar.gz (GitHub release asset).
ARG ASYNC_PROFILER_SHA256=1233f26fc95753e75ce32733bbcaf8f0bedc2c098b0e798af87935b08a63b24e

# tar/gzip are only needed to unpack async-profiler at build time. curl (curl-minimal),
# bash, sed, and coreutils (stat/ls/sha256sum) ship in the Corretto AL2023 base and are
# used by the runtime loop.
RUN yum install -y tar gzip && yum clean all

# Bake async-profiler into the image (no runtime GitHub fetch); verify the download.
RUN curl -sSL -o /tmp/ap.tgz \
      "https://github.com/async-profiler/async-profiler/releases/download/v${ASYNC_PROFILER_VERSION}/async-profiler-${ASYNC_PROFILER_VERSION}-linux-${TARGETARCH}.tar.gz" \
  && echo "${ASYNC_PROFILER_SHA256}  /tmp/ap.tgz" | sha256sum -c - \
  && mkdir -p /opt/async-profiler \
  && tar -xz -C /opt/async-profiler --strip-components=1 -f /tmp/ap.tgz \
  && rm -f /tmp/ap.tgz \
  && test -f /opt/async-profiler/lib/libasyncProfiler.so

COPY profile-loop.sh /usr/local/bin/profile-loop.sh
# On-demand /dump endpoint (JDK 25 single-file source mode; jcmd ships in Corretto).
COPY DumpServer.java /usr/local/bin/DumpServer.java
RUN chmod +x /usr/local/bin/profile-loop.sh

# Run as the workshop app's UID by default; the inject policy sets runAsUser to the
# app's UID explicitly (JVM dynamic attach requires the same UID as the target).
USER 1000:1000
ENV AP_HOME=/opt/async-profiler
ENTRYPOINT ["/usr/local/bin/profile-loop.sh"]
