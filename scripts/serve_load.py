#!/usr/bin/env python3
"""Time a running fixture `serve` the way the phone loads it.

Reads the bearer header from --token-header (never printed). For each path it reports
sequential latency (median and range over --runs after one warm-up), the server's CPU
time per request (from `ps`, when --pid is given), and the wall time for --burst
identical requests sent at once (median and range over --runs), with the count of
non-200 answers. Use only against a verify run's server, never port 8787.
"""
import argparse
import concurrent.futures
import json
import statistics
import subprocess
import time
import urllib.error
import urllib.request


def cpu_seconds(pid):
    out = subprocess.run(['ps', '-o', 'time=', '-p', str(pid)], capture_output=True, text=True, check=True).stdout.strip()
    parts = [float(p) for p in out.replace('-', ':').split(':')]
    total = 0.0
    for p in parts:
        total = total * 60 + p
    return total


def fetch(url, header):
    name, value = header.split(':', 1)
    request = urllib.request.Request(url, headers={name.strip(): value.strip()})
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as e:
        body, status = e.read(), e.code
    return time.perf_counter() - start, status, len(body)


def summary(values):
    return {'median_ms': round(statistics.median(values) * 1000), 'min_ms': round(min(values) * 1000), 'max_ms': round(max(values) * 1000)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--token-header', required=True)
    parser.add_argument('--pid', type=int)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--burst', type=int, default=8)
    parser.add_argument('paths', nargs='*', default=['/v2/snapshot', '/v2/day'])
    args = parser.parse_args()
    if args.port == 8787:
        parser.error('never 8787')
    with open(args.token_header) as f:
        header = f.read().strip()
    for path in args.paths:
        url = 'http://127.0.0.1:%d%s' % (args.port, path)
        fetch(url, header)
        before = cpu_seconds(args.pid) if args.pid else None
        sequential, failures, size = [], 0, 0
        for _ in range(args.runs):
            seconds, status, size = fetch(url, header)
            sequential.append(seconds)
            failures += status != 200
        cpu = (cpu_seconds(args.pid) - before) / args.runs if args.pid else None
        bursts = []
        with concurrent.futures.ThreadPoolExecutor(args.burst) as pool:
            for _ in range(args.runs):
                start = time.perf_counter()
                results = list(pool.map(lambda _: fetch(url, header), range(args.burst)))
                bursts.append(time.perf_counter() - start)
                failures += sum(status != 200 for _, status, _ in results)
        print(json.dumps({'path': path, 'bytes': size, 'sequential': summary(sequential),
                          'server_cpu_ms_per_request': round(cpu * 1000) if cpu is not None else None,
                          'burst': args.burst, 'burst_wall': summary(bursts), 'non_200': failures}))


if __name__ == '__main__':
    main()
