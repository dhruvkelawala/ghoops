#!/usr/bin/env python3
"""Scan files or reachable Git history for release secrets."""

import argparse
from collections import Counter, defaultdict
import json
import os
from pathlib import Path
import re
import subprocess
import sys


SHAPES = {
    "pairing link": (b"ghealth://pair?", rb"ghealth://pair\?[^\s\"'<>]+"),
    "Google access token": (b"ya29.", rb"ya29\.[A-Za-z0-9._~-]+"),
    "Google refresh token": (b"1//", rb"(?<![A-Za-z0-9_])1//[A-Za-z0-9_-]{6,}"),
    "Google client secret": (b"GOCSPX-", rb"GOCSPX-[A-Za-z0-9_-]+"),
    "Google client ID": (
        b".apps.googleusercontent.com",
        rb"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]+\.apps\.googleusercontent\.com\b",
    ),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("needle_file", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()

    try:
        needles = args.needle_file.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        print("Cannot read the needle file.", file=sys.stderr)
        return 2
    for line, needle in enumerate(needles, 1):
        if len(needle) < 6:
            print(f"Needle line {line} must have at least six characters.", file=sys.stderr)
            return 2

    scan = Scan(needles)
    try:
        if args.target.is_symlink() or not args.target.is_dir():
            scan_files(args.target, scan)
        else:
            git = GitTarget(args.target)
            if git.is_repo():
                scan_history(git, scan)
            else:
                scan_files(args.target, scan)
    except (OSError, ValueError, subprocess.CalledProcessError):
        print("Cannot scan the complete target.", file=sys.stderr)
        return 2

    report = scan.report()
    print(json.dumps(report))
    return int(bool(report["hits"]))


class Scan:
    def __init__(self, needles):
        self.needles = [needle.encode("utf-8") for needle in needles]
        self.shapes = [
            (label, prefix, re.compile(pattern))
            for label, (prefix, pattern) in SHAPES.items()
        ]
        self.paths = defaultdict(Counter)
        self.metadata = Counter()
        self.commits_hit = 0

    def find(self, data):
        hits = Counter()
        for line, needle in enumerate(self.needles, 1):
            if count := data.count(needle):
                hits[line] = count
        for label, prefix, pattern in self.shapes:
            if prefix in data:
                if count := sum(1 for _ in pattern.finditer(data)):
                    hits[label] = count
        return hits

    def report(self):
        hits = [
            {"path": None, "source": "commit metadata", **hit(label, count)}
            for label, count in self.metadata.items()
        ]
        for raw_path, counts in sorted(self.paths.items()):
            path = os.fsdecode(raw_path)
            if self.find(raw_path) or self.find(json.dumps(path).encode("ascii")):
                path = None
            hits.extend({"path": path, **hit(label, count)} for label, count in counts.items())
        return {
            "commits_hit": self.commits_hit,
            "paths_hit": len(self.paths),
            "needle_lines": sorted({row["needle_line"] for row in hits if "needle_line" in row}),
            "hits": hits,
        }


def hit(label, count):
    key = "needle_line" if isinstance(label, int) else "shape"
    return {key: label, "count": count}


def scan_files(target, scan):
    def scan_path(path, name):
        raw_name = os.fsencode(name)
        hits = scan.find(raw_name)
        if path.is_symlink():
            hits.update(scan.find(os.fsencode(os.readlink(path))))
        elif path.is_file():
            hits.update(scan.find(path.read_bytes()))
        elif not path.is_dir():
            raise OSError
        if hits:
            scan.paths[raw_name].update(hits)

    def raise_error(error):
        raise error

    if target.is_symlink() or not target.is_dir():
        scan_path(target, target.name)
        return
    for folder, dirs, files in os.walk(target, onerror=raise_error):
        for entry in dirs + files:
            path = Path(folder) / entry
            scan_path(path, path.relative_to(target))


class GitTarget:
    def __init__(self, target):
        self.target = target
        local_vars = subprocess.check_output(
            ["git", "rev-parse", "--local-env-vars"], stderr=subprocess.DEVNULL
        ).decode("ascii").splitlines()
        self.env = {key: value for key, value in os.environ.items() if key not in local_vars}

    def command(self, *args):
        return ["git", "--no-replace-objects", "-C", self.target, *args]

    def read(self, *args):
        return subprocess.check_output(self.command(*args), env=self.env, stderr=subprocess.DEVNULL)

    def is_repo(self):
        if (self.target / ".git").exists():
            return True
        try:
            return self.read("rev-parse", "--is-bare-repository") == b"true\n"
        except subprocess.CalledProcessError:
            return False


def scan_history(git, scan):
    """Count hit commits and report each path's distinct blob versions once."""
    if git.read("rev-parse", "--is-shallow-repository") != b"false\n":
        raise ValueError

    blobs = {}
    names = {}
    seen = set()
    trees = {}
    with subprocess.Popen(
        git.command("cat-file", "--batch"), env=git.env,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    ) as objects:
        for commit in git.read("rev-list", "--all").splitlines():
            raw_commit = read_object(objects, commit)
            metadata = scan.find(raw_commit)
            scan.metadata.update(metadata)
            tree_header, _, _ = raw_commit.partition(b"\n")
            kind, _, tree = tree_header.partition(b" ")
            if kind != b"tree" or not tree:
                raise ValueError
            if tree not in trees:
                tree_hit = False
                for entry in git.read("ls-tree", "-rz", "--full-tree", tree).split(b"\0")[:-1]:
                    header, path = entry.split(b"\t", 1)
                    _, kind, oid = header.split()
                    if path not in names:
                        names[path] = scan.find(path)
                        if names[path]:
                            scan.paths[path].update(names[path])
                    if kind == b"blob" and oid not in blobs:
                        blobs[oid] = scan.find(read_object(objects, oid))
                    content = blobs.get(oid)
                    if content and (path, oid) not in seen:
                        scan.paths[path].update(content)
                        seen.add((path, oid))
                    if names[path] or content:
                        tree_hit = True
                trees[tree] = tree_hit
            if metadata or trees[tree]:
                scan.commits_hit += 1
        objects.stdin.close()
        if objects.wait():
            raise OSError


def read_object(objects, oid):
    objects.stdin.write(oid + b"\n")
    objects.stdin.flush()
    fields = objects.stdout.readline().split()
    if len(fields) != 3:
        raise ValueError
    size = int(fields[2])
    data = objects.stdout.read(size)
    if len(data) != size or objects.stdout.read(1) != b"\n":
        raise ValueError
    return data


if __name__ == "__main__":
    sys.exit(main())
