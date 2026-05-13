#!/usr/bin/env python3
"""
scripts/_class_tagging_splice.py

Splice helper for the class-tagging template. Called by
scripts/apply-class-tagging-template.sh — kept as a separate Python file
because the work (BEGIN/END extraction, h2 splice-point detection, atomic
write, byte-identity preservation, unified diff for --dry-run) is cleaner
in Python than in bash + awk on bash 3.2 / BSD sed (macOS).

Usage (called by the bash wrapper, not directly by humans):

    python3 scripts/_class_tagging_splice.py [--dry-run] <persona-path>

Exit codes:
    0 — splice applied (or skip on idempotent re-run)
    1 — generic failure (template missing, file unreadable, IO error)
    2 — malformed input (BEGIN without END, etc.)
    3 — eligibility refused (judge.md, synthesis.md, _templates/...)

Race-safe writes: writes to <target>.tmp.<pid> in the same directory and
os.replace()s onto the target. Same-FS atomic on POSIX.
"""

import argparse
import difflib
import os
import re
import sys
import tempfile

BEGIN_SENTINEL = "<!-- BEGIN class-tagging -->"
END_SENTINEL = "<!-- END class-tagging -->"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_PATH = os.path.join(
    REPO_ROOT, "personas", "_templates", "class-tagging.md"
)

# Personas with hand-written class-aware sections (W2.3/W2.4); never splice.
NOT_APPLICABLE_BASENAMES = ("judge.md", "synthesis.md")
# Match: ## <Output|Verdict> <anything-else-on-line>
H2_SPLICE_RE = re.compile(r"^##\s+(Output|Verdict)\b.*$")


def _expanduser(p):
    """Honor literal ~/ even when the value came in via a config read."""
    if p.startswith("~"):
        return os.path.expanduser(p)
    return p


def extract_template_payload(template_path):
    """Return the EXACT bytes between (and including) the BEGIN/END sentinels.

    Reading and returning as text is fine — the file is plain UTF-8 markdown.
    Byte-identity is preserved because we don't mutate whitespace.
    """
    with open(template_path, "r", encoding="utf-8") as f:
        text = f.read()
    begin_idx = text.find(BEGIN_SENTINEL)
    if begin_idx < 0:
        raise RuntimeError(
            "template missing BEGIN sentinel: %s" % template_path
        )
    end_idx = text.find(END_SENTINEL, begin_idx)
    if end_idx < 0:
        raise RuntimeError(
            "template missing END sentinel: %s" % template_path
        )
    end_line_end = text.find("\n", end_idx)
    if end_line_end < 0:
        # END sentinel is the final line, no trailing newline in source
        payload = text[begin_idx:]
    else:
        payload = text[begin_idx:end_line_end]
    return payload


def check_target_eligibility(target_path):
    """Return None if eligible; raise SystemExit(3) with a stderr message if not."""
    abspath = os.path.abspath(target_path)
    rel = os.path.relpath(abspath, REPO_ROOT)
    parts = rel.split(os.sep)

    # Must be under personas/{review,design,check}/
    if len(parts) < 3 or parts[0] != "personas" or parts[1] not in (
        "review",
        "design",
        "check",
    ):
        sys.stderr.write(
            "error: ineligible path (must be under personas/{review,design,check}/): "
            "%s\n" % target_path
        )
        sys.exit(3)

    # Refuse hand-written class-aware files
    if os.path.basename(abspath) in NOT_APPLICABLE_BASENAMES:
        sys.stderr.write(
            "error: refusing to splice hand-written class-aware persona: %s\n"
            % target_path
        )
        sys.exit(3)
    if "_templates" in parts:
        sys.stderr.write(
            "error: refusing to splice into template directory: %s\n"
            % target_path
        )
        sys.exit(3)


def detect_malformed(text, path):
    """If BEGIN appears without matching END, exit 2 per CLI contract."""
    begin_idx = text.find(BEGIN_SENTINEL)
    if begin_idx < 0:
        return False  # not spliced; nothing to validate
    end_idx = text.find(END_SENTINEL, begin_idx)
    if end_idx < 0:
        sys.stderr.write(
            "malformed: BEGIN without END at %s\n" % path
        )
        sys.exit(2)
    return True  # already spliced (well-formed)


def find_splice_point(text):
    """Return the byte offset where the splice block should be inserted.

    Splice happens ABOVE the first matching h2 heading (## Output... or
    ## Verdict...). If no match, splice at end-of-file.

    Returns (offset, mode) where mode is 'h2' or 'eof'.
    """
    pos = 0
    while pos < len(text):
        nl = text.find("\n", pos)
        line_end = nl if nl >= 0 else len(text)
        line = text[pos:line_end]
        if H2_SPLICE_RE.match(line):
            return (pos, "h2")
        if nl < 0:
            break
        pos = nl + 1
    return (len(text), "eof")


def build_spliced_content(original, payload):
    """Return what the file would look like after splicing.

    Insertion rules:
      - h2 mode: insert payload + two newlines BEFORE the heading; leave a
        blank line above the payload if the preceding text doesn't end in
        \\n\\n already.
      - eof mode: append payload preceded by a blank line; preserve final
        newline on the original.
    """
    offset, mode = find_splice_point(original)

    if mode == "h2":
        before = original[:offset]
        after = original[offset:]
        # Ensure single blank line separating payload from preceding text
        if not before.endswith("\n\n"):
            if before.endswith("\n"):
                before = before + "\n"
            else:
                before = before + "\n\n"
        block = payload + "\n\n"
        return before + block + after

    # eof mode
    before = original
    if before == "":
        return payload + "\n"
    if not before.endswith("\n"):
        before = before + "\n"
    # Insert one blank line between body and payload
    if not before.endswith("\n\n"):
        before = before + "\n"
    return before + payload + "\n"


def atomic_write(target_path, new_content):
    """Write new_content to target_path atomically (same-FS rename)."""
    target_dir = os.path.dirname(os.path.abspath(target_path)) or "."
    fd, tmp_path = tempfile.mkstemp(
        prefix=".cls-splice-", suffix=".tmp", dir=target_dir
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_content)
        # Preserve permissions of the original file
        try:
            st = os.stat(target_path)
            os.chmod(tmp_path, st.st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp_path, target_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def emit_unified_diff(orig_path, original, new_content):
    """Print a unified diff to stdout (no file write)."""
    diff = difflib.unified_diff(
        original.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile=orig_path,
        tofile=orig_path + " (after splice)",
        n=3,
    )
    sys.stdout.writelines(diff)


def process_file(target_path, dry_run):
    """Process one file. Returns one of: 'splice', 'skip', 'dry-run'."""
    target_path = _expanduser(target_path)

    check_target_eligibility(target_path)

    if not os.path.isfile(target_path):
        sys.stderr.write("error: not a file: %s\n" % target_path)
        sys.exit(1)

    with open(target_path, "r", encoding="utf-8") as f:
        original = f.read()

    if detect_malformed(original, target_path):
        # Already spliced (BEGIN+END both present) → idempotent skip.
        sys.stderr.write("skip (already spliced): %s\n" % target_path)
        return "skip"

    payload = extract_template_payload(TEMPLATE_PATH)
    new_content = build_spliced_content(original, payload)

    if dry_run:
        emit_unified_diff(target_path, original, new_content)
        return "dry-run"

    atomic_write(target_path, new_content)
    return "splice"


def main(argv):
    p = argparse.ArgumentParser(
        description="Splice the class-tagging template into one persona file."
    )
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("path")
    args = p.parse_args(argv)
    return process_file(args.path, args.dry_run)


if __name__ == "__main__":
    try:
        result = main(sys.argv[1:])
        sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        sys.stderr.write("error: %s\n" % e)
        sys.exit(1)
