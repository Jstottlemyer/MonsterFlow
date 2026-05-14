#!/usr/bin/env python3
"""_uninstall_helpers.py — uninstall.sh's Python backend.

MVP scope (cold-start / detector-fallback mode only; manifest emission deferred
to a future install-sh-manifest-emit spec). All shell-unfriendly work lives
here: filesystem detection, sentinel-block parsing, sha256 verification,
backup-disposition decisions. uninstall.sh invokes via $(python3 ... subcmd args)
per feedback_hook_stdin_heredoc — never via heredoc-on-stdin.

Subcommands:
  parse-manifest <path>                       → JSONL rows (or empty + exit 2 in cold-start)
  detect-fallback-symlinks <home> <repo>      → synthesized symlink JSONL rows for cold-start
  detect-fallback-backup <dst>                → action JSONL: {action: "restore"|"skip"|"none", ...}
  strip-sentinel-block <file> <begin> <end>   → strip in place; print "stripped=N"
  sha256-check <file> <hex>                   → exit 0 on match, 1 on mismatch, 2 on missing
  tombstone-manifest <path>                   → stub (returns "no-manifest" in cold-start)

Stdlib only; no external deps.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path


# --------- detector-fallback: symlink discovery ---------

CLAUDE_SUBDIRS = (
    "commands",
    "agents",
    "personas",
    "templates",
    "hooks",
    "scripts",
    "skills",
    "schemas",
    "domain-agents",
)


def _is_monsterflow_target(target: str, repo: str) -> bool:
    """Match symlink target against repo dir or pre-rebrand claude-workflow path."""
    return ("/MonsterFlow/" in target) or ("/claude-workflow/" in target) or target.startswith(repo)


def _emit(row: dict) -> None:
    sys.stdout.write(json.dumps(row, separators=(",", ":")) + "\n")


def cmd_detect_fallback_symlinks(home: str, repo: str) -> int:
    """Walk ~/.claude/* looking for symlinks pointing into the repo. Also
    cover the file-level symlinks settings.json + the theme/knowledge layer
    paths under ~/.config and ~/.tmux.conf and ~/.local/bin."""
    home_p = Path(home)
    repo_abs = str(Path(repo).resolve())

    # ~/.claude/ subdir trees (recursive)
    claude_root = home_p / ".claude"
    if claude_root.is_dir():
        for subdir_name in CLAUDE_SUBDIRS:
            sub = claude_root / subdir_name
            if not sub.exists():
                continue
            for path in sub.rglob("*"):
                if not path.is_symlink():
                    continue
                target = os.readlink(path)
                if _is_monsterflow_target(target, repo_abs):
                    _emit({
                        "op": "symlink",
                        "dst": str(path),
                        "src": target,
                        "source": "fallback",
                    })

    # ~/.claude/settings.json (file-level symlink, not under a subdir)
    settings = claude_root / "settings.json"
    if settings.is_symlink():
        target = os.readlink(settings)
        if _is_monsterflow_target(target, repo_abs):
            _emit({"op": "symlink", "dst": str(settings), "src": target, "source": "fallback"})

    # Single-file symlinks installed by the theme + knowledge layer
    candidates = [
        home_p / ".tmux.conf",
        home_p / ".config" / "cmux" / "cmux.json",
        home_p / ".config" / "ghostty" / "config",
        home_p / ".local" / "bin" / "autorun",
        # graphify is a venv-shimmed symlink; leave alone per spec OOS (third-party)
    ]
    for c in candidates:
        if c.is_symlink():
            target = os.readlink(c)
            if _is_monsterflow_target(target, repo_abs):
                _emit({"op": "symlink", "dst": str(c), "src": target, "source": "fallback"})

    return 0


def cmd_detect_fallback_backup(dst: str) -> int:
    """Decide what to do with a symlink-replaced target's .bak.<ts> files.

    Conservative cold-start rule (per design D6 detector-fallback): restore
    only when exactly one .bak file exists AND its mtime predates the symlink's
    ctime. Anything ambiguous → leave backups in place, remove symlink only.
    """
    dst_p = Path(dst)
    parent = dst_p.parent
    name = dst_p.name
    backups = sorted(parent.glob(f"{name}.bak.*"))
    if not backups:
        _emit({"dst": dst, "action": "none", "reason": "no-backup"})
        return 0
    if len(backups) > 1:
        _emit({"dst": dst, "action": "skip", "reason": "ambiguous", "count": len(backups)})
        return 0
    backup = backups[0]
    try:
        # symlink ctime is the time the symlink was created (install time)
        symlink_ctime = dst_p.lstat().st_ctime
        backup_mtime = backup.stat().st_mtime
    except FileNotFoundError:
        _emit({"dst": dst, "action": "skip", "reason": "stat-failed"})
        return 0
    if backup_mtime > symlink_ctime:
        _emit({"dst": dst, "action": "skip", "reason": "newer-than-symlink", "backup": str(backup)})
        return 0
    _emit({"dst": dst, "action": "restore", "backup": str(backup)})
    return 0


# --------- sentinel-block strip ---------

def cmd_strip_sentinel_block(file: str, begin: str, end: str) -> int:
    """Strip every line range from BEGIN to END (inclusive) in-place.
    Refuses if BEGIN found without matching END (unbalanced).
    Atomic write via same-dir tmp + os.replace.
    """
    p = Path(file)
    if not p.exists():
        sys.stderr.write(f"strip-sentinel-block: {file} not found\n")
        return 2

    # Follow if symlink (per Edge Case 11): write goes to the target
    real = p.resolve()
    text = real.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    out_lines: list[str] = []
    stripped = 0
    inside = False
    pending_begin_lineno: int | None = None

    for i, line in enumerate(lines, start=1):
        bare = line.rstrip("\n").rstrip("\r")
        if not inside and bare == begin:
            inside = True
            pending_begin_lineno = i
            continue
        if inside:
            if bare == end:
                inside = False
                stripped += 1
                pending_begin_lineno = None
                continue
            # consume — inside a block
            continue
        out_lines.append(line)

    if inside:
        sys.stderr.write(
            f"strip-sentinel-block: unbalanced — BEGIN at line {pending_begin_lineno} "
            f"with no matching END; refusing to strip {file}\n"
        )
        return 1

    # Atomic write to real (the underlying file if symlinked)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(real.parent), prefix=f".{real.name}.tmp.")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.writelines(out_lines)
        os.replace(tmp_path, real)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

    print(f"stripped={stripped}")
    return 0


# --------- SHA256 check ---------

def cmd_sha256_check(file: str, expected_hex: str) -> int:
    p = Path(file)
    if not p.exists():
        sys.stderr.write(f"sha256-check: {file} not found\n")
        return 2
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    actual = h.hexdigest()
    if actual == expected_hex:
        return 0
    sys.stderr.write(f"sha256-check: mismatch (expected {expected_hex}, got {actual})\n")
    return 1


# --------- parse-manifest (cold-start stub) ---------

def cmd_parse_manifest(path: str, repo_dir: str | None = None) -> int:
    """Cold-start MVP: manifest doesn't exist yet. Exit 2 + no output so
    uninstall.sh falls through to detector mode."""
    if not Path(path).exists():
        sys.stderr.write(f"parse-manifest: no manifest at {path} — cold-start mode\n")
        return 2
    # If a manifest exists (future), parse and emit rows. For MVP, refuse +
    # tell adopter to wait for the install-sh-manifest-emit feature.
    sys.stderr.write(
        f"parse-manifest: manifest found at {path} but this build is cold-start-only "
        "(install-sh-manifest-emit not yet shipped). Falling through to detector mode.\n"
    )
    return 2


# --------- tombstone-manifest (cold-start stub) ---------

def cmd_tombstone_manifest(path: str) -> int:
    """Cold-start MVP: no active manifest to tombstone."""
    if not Path(path).exists():
        print(f"tombstone: no-manifest")
        return 0
    ts = _dt.datetime.now(_dt.timezone.utc).strftime("%Y%m%d%H%M%S")
    new_path = f"{path}.uninstalled.{ts}"
    os.replace(path, new_path)
    print(f"tombstone: {new_path}")
    return 0


# --------- CLI dispatch ---------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_pm = sub.add_parser("parse-manifest")
    p_pm.add_argument("path")
    p_pm.add_argument("--repo-dir", default=None)

    p_dfs = sub.add_parser("detect-fallback-symlinks")
    p_dfs.add_argument("home")
    p_dfs.add_argument("repo")

    p_dfb = sub.add_parser("detect-fallback-backup")
    p_dfb.add_argument("dst")

    p_strip = sub.add_parser("strip-sentinel-block")
    p_strip.add_argument("file")
    p_strip.add_argument("begin")
    p_strip.add_argument("end")

    p_sha = sub.add_parser("sha256-check")
    p_sha.add_argument("file")
    p_sha.add_argument("hex")

    p_tomb = sub.add_parser("tombstone-manifest")
    p_tomb.add_argument("path")

    args = parser.parse_args(argv)

    if args.cmd == "parse-manifest":
        return cmd_parse_manifest(args.path, args.repo_dir)
    if args.cmd == "detect-fallback-symlinks":
        return cmd_detect_fallback_symlinks(args.home, args.repo)
    if args.cmd == "detect-fallback-backup":
        return cmd_detect_fallback_backup(args.dst)
    if args.cmd == "strip-sentinel-block":
        return cmd_strip_sentinel_block(args.file, args.begin, args.end)
    if args.cmd == "sha256-check":
        return cmd_sha256_check(args.file, args.hex)
    if args.cmd == "tombstone-manifest":
        return cmd_tombstone_manifest(args.path)

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
