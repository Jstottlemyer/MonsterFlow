#!/usr/bin/env python3
"""Split one commit's diff into per-PR patches by file and by hunk.

SPIKE: as used to split one Red Rabbit build commit (T2.1/T2.2a/T2.4) into
PR-4a/4b/4c on 2026-10-02. FILE_4B, FILE_4C and STORAGE are that commit's
rules; a real version would take the grouping rules as input.

usage: split_hunks.py <repo> <commit> <outdir>

Writes <outdir>/{4a,4b,4c}.patch and prints a report. Rules:
  - files matching FILE_4B / FILE_4C go wholly to that group;
  - in every other file, a hunk whose changed lines all match STORAGE
    (the T2.4 KV-facade import swap) goes to 4c, any other hunk to 4a;
    a hunk mixing both kinds is reported as MIXED and kept in 4a.
"""
import re, subprocess, sys, os

repo, commit, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)

FILE_4B = re.compile(r"^(apps/cms/pages/api/mcp\.ts|packages/mcp-server/|apps/cms/tests/unit/api/mcp-route-scoped\.test\.ts|docs/.*/T2\.2a-)")
FILE_4C = re.compile(r"^(packages/canon-access/src/store/|packages/canon-access/tests/store-|apps/cms/src/lib/legacy-kv\.ts|apps/cms/tests/unit/legacy-kv\.test\.ts|scripts/lint/allowlists/storage-clients\.json|docs/.*/T2\.4-)")
STORAGE = re.compile(r"legacy-kv|kv-client|@vercel/kv|canon-access/store|\bkv\b|Kv\b|KvLike|rolesCacheKv|relmapCacheKv|from '@/lib/kv'")

diff = subprocess.run(["git", "-C", repo, "show", "--format=", "--no-color", "-U3", commit],
                      capture_output=True, text=True, check=True).stdout
files = re.split(r"(?m)^(?=diff --git )", diff)
groups = {"4a": [], "4b": [], "4c": []}
report = []
for f in files:
    if not f.strip():
        continue
    m = re.match(r"diff --git a/(\S+) b/(\S+)", f)
    path = m.group(2)
    if FILE_4B.match(path):
        groups["4b"].append(f); report.append(("4b", path, "file")); continue
    if FILE_4C.match(path):
        groups["4c"].append(f); report.append(("4c", path, "file")); continue
    head, *hunks = re.split(r"(?m)^(?=@@ )", f)
    if not hunks:  # binary / mode-only / new empty file
        groups["4a"].append(f); report.append(("4a", path, "file")); continue
    a_h, c_h, mixed = [], [], 0
    for h in hunks:
        changed = [l[1:] for l in h.splitlines()[1:] if l[:1] in "+-"]
        st = [STORAGE.search(l) is not None for l in changed if l.strip()]
        if st and all(st):
            c_h.append(h)
        else:
            if any(st):
                mixed += 1
            a_h.append(h)
    if a_h:
        groups["4a"].append(head + "".join(a_h))
    if c_h:
        groups["4c"].append(head + "".join(c_h))
    kind = "split" if (a_h and c_h) else ("4c" if c_h else "4a")
    report.append((kind, path, f"4a={len(a_h)} 4c={len(c_h)} mixed={mixed}"))

for g, parts in groups.items():
    with open(os.path.join(out, f"{g}.patch"), "w") as fh:
        fh.write("".join(parts))
for kind, path, info in sorted(report):
    print(f"{kind:5} {path:75} {info}")
