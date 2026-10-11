#!/usr/bin/env python3
"""pyroscope-shares.py [--url URL] [--service NAME] WINDOW... — share of a pod's CPU
samples spent in the JIT compiler, class loading, GC and the interpreter.

WINDOW is "label|pod-suffix|from|to" with ISO UTC times, for example
"baseline first 60s|vqlh7|2026-10-11T08:36:05Z|2026-10-11T08:37:05Z". Start a window at
the pod's first upload (the first non-zero sample of its timeline), not at its creation.

Per window: GET /pyroscope/render for the process CPU profile, then per category the
union of the frame spans whose name matches (nested matches are counted once), divided
by the total. Use the shares only: the CPU totals of short windows are not reliable
(uploads arrive in 15 s buckets). Runs on the IDE, where Pyroscope is reachable through
a port-forward (see pyroscope-shares.sh).
"""
import argparse
import datetime as dt
import json
import urllib.parse
import urllib.request

CPU = 'process_cpu:cpu:nanoseconds:cpu:nanoseconds'
CATEGORIES = {
    'JIT compiler': ['CompileBroker::compiler_thread_loop'],
    'class loading': ['ClassLoader', 'ClassLoading', 'SystemDictionary::', 'ClassFileParser'],
    'GC': ['G1', 'SerialHeap', 'GenCollectedHeap', 'DefNewGeneration', 'TenuredGeneration',
           'GCTaskThread', 'VM_GC'],
    'interpreter': ['Interpreter'],
}


def epoch_ms(iso):
    return int(dt.datetime.fromisoformat(iso.replace('Z', '+00:00')).timestamp() * 1000)


def union(spans):
    total, cur = 0, None
    for a, b in sorted(spans):
        if cur and a <= cur[1]:
            cur[1] = max(cur[1], b)
        else:
            if cur:
                total += cur[1] - cur[0]
            cur = [a, b]
    return total + (cur[1] - cur[0] if cur else 0)


def shares(url, service, pod, start, end):
    query = f'{CPU}{{service_name="{service}",pod=~".*{pod}"}}'
    params = urllib.parse.urlencode(
        {'query': query, 'from': epoch_ms(start), 'until': epoch_ms(end), 'format': 'json'})
    fb = json.load(urllib.request.urlopen(f'{url}/pyroscope/render?{params}'))['flamebearer']
    names, total = fb['names'], fb['numTicks']
    if not total:
        return 0, {}
    spans = {k: [] for k in CATEGORIES}
    for level in fb['levels']:
        x = 0
        for i in range(0, len(level), 4):
            offset, width, _self, name = level[i:i + 4]
            x += offset
            for k, patterns in CATEGORIES.items():
                if any(p in names[name] for p in patterns):
                    spans[k].append((x, x + width))
            x += width
    return total / 1e9, {k: 100 * union(v) / total for k, v in spans.items()}


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', default='http://localhost:4040')
    ap.add_argument('--service', default='unicorn-store-spring')
    ap.add_argument('windows', nargs='+', metavar='WINDOW')
    args = ap.parse_args()
    for w in args.windows:
        label, pod, start, end = w.split('|')
        cpu, pct = shares(args.url, args.service, pod, start, end)
        if not pct:
            print(f'{label:34s} no samples')
            continue
        print(f'{label:34s} cpu {cpu:6.1f}s  ' + ', '.join(f'{k} {v:.0f}%' for k, v in pct.items()))
