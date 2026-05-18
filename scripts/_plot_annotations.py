#!/usr/bin/env python3
"""
scripts/_plot_annotations.py

Deterministic annotation helpers for Plot Document files. Called by
commands/plot.md and wrap Phase 2d — kept as a separate Python file
because structured markdown surgery (callout injection, dedup,
renumbering, link extraction) is cleaner in Python than in bash + awk
on bash 3.2 / BSD sed (macOS).

Both CLI and importable API:

    # CLI
    python3 scripts/_plot_annotations.py inject-stale --file F --section S --reason R
    python3 scripts/_plot_annotations.py remove-stale --file F --section S
    python3 scripts/_plot_annotations.py inject-draft --file F --section S
    python3 scripts/_plot_annotations.py remove-draft --file F --section S
    python3 scripts/_plot_annotations.py extract-links --file F [--repo-root R]
    python3 scripts/_plot_annotations.py status --file F

    # Importable
    from scripts._plot_annotations import inject_stale, remove_stale, ...

Exit codes:
    0 — success
    1 — generic failure (file unreadable, section not found, IO error)

Race-safe writes: writes to <target>.tmp.<random> in the same directory
and os.replace()s onto the target. Same-FS atomic on POSIX.
"""

import argparse
import datetime
import os
import re
import sys
import tempfile

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Heading pattern: one or more '#' followed by a space and the heading text.
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+)$")

# Callout patterns — match the first line of a callout block.
STALE_CALLOUT_RE = re.compile(r"^>\s*\[!STALE\]")
DRAFT_CALLOUT_RE = re.compile(r"^>\s*\[!DRAFT\]")

# Numbered reason inside a STALE callout: "> (N) reason text (detected DATE)."
# or the first line: "> [!STALE] (N) reason text (detected DATE)."
STALE_REASON_RE = re.compile(
    r"^>\s*(?:\[!STALE\]\s*)?\((\d+)\)\s+(.+?)\s*"
    r"\(detected\s+(\d{4}-\d{2}-\d{2})\)\.?\s*$"
)

# Markdown link: [text](target)
LINK_RE = re.compile(r"\[(?:[^\]]*)\]\(([^)]+)\)")

# Maximum stale reasons before oldest-drop.
MAX_STALE_REASONS = 3

# TODO: add path containment when Phase 4 CI gate ships (reject absolute
# paths, .. traversal, symlink escapes via realpath, URL-scheme links;
# anchor to git rev-parse --show-toplevel)


# ---------------------------------------------------------------------------
# Helpers — section detection
# ---------------------------------------------------------------------------

def _today():
    """Return today's date as YYYY-MM-DD string."""
    return datetime.date.today().isoformat()


def _parse_heading(line):
    """Return (level, text) if *line* is a markdown heading, else None.

    Level is the number of '#' characters (1-6). Text is the heading
    content after the '#' markers and separating space, stripped.
    """
    m = HEADING_RE.match(line)
    if m:
        return len(m.group(1)), m.group(2).strip()
    return None


def _find_section(lines, section_name):
    """Return (start, end, level) for the section named *section_name*.

    *start* is the index of the heading line.
    *end* is the index of the first line AFTER the section content (the
    next heading of same-or-higher level, or len(lines)).
    *level* is the heading level (number of '#' characters).

    Raises ValueError if the section is not found.
    """
    start = None
    level = None
    for i, line in enumerate(lines):
        parsed = _parse_heading(line)
        if parsed is None:
            continue
        h_level, h_text = parsed
        if start is None:
            if h_text == section_name:
                start = i
                level = h_level
        else:
            # We are inside the target section — check for same-or-higher
            # level heading that terminates it.
            if h_level <= level:
                return start, i, level
    if start is not None:
        return start, len(lines), level
    raise ValueError("section not found: %s" % section_name)


# ---------------------------------------------------------------------------
# Helpers — callout block detection
# ---------------------------------------------------------------------------

def _find_callout_block(lines, start_idx, end_idx, callout_re):
    """Find a callout block matching *callout_re* within lines[start_idx:end_idx].

    Returns (block_start, block_end) where block_start is the index of the
    first line of the callout and block_end is the index of the first line
    AFTER the callout block. A callout block is contiguous lines starting
    with '> '.

    Returns None if no matching callout is found.
    """
    block_start = None
    for i in range(start_idx, end_idx):
        line = lines[i]
        if block_start is None:
            if callout_re.match(line):
                block_start = i
        else:
            # Inside the callout block — extend while lines start with '> '.
            if not line.startswith("> "):
                return block_start, i
    if block_start is not None:
        return block_start, end_idx
    return None


def _parse_stale_reasons(lines, block_start, block_end):
    """Extract numbered reasons from a STALE callout block.

    Returns a list of (number, reason_text, date_str) tuples.
    """
    reasons = []
    for i in range(block_start, block_end):
        m = STALE_REASON_RE.match(lines[i])
        if m:
            reasons.append((int(m.group(1)), m.group(2), m.group(3)))
    return reasons


# ---------------------------------------------------------------------------
# Helpers — atomic write
# ---------------------------------------------------------------------------

def _atomic_write(target_path, content):
    """Write *content* to *target_path* atomically (same-FS rename)."""
    target_dir = os.path.dirname(os.path.abspath(target_path)) or "."
    fd, tmp_path = tempfile.mkstemp(
        prefix=".plot-annot-", suffix=".tmp", dir=target_dir
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        # Preserve permissions of the original file.
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


def _read_file(path):
    """Read a UTF-8 file and return its content as a string."""
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _write_lines(path, lines):
    """Join *lines* with newlines and atomically write to *path*."""
    content = "\n".join(lines)
    # Preserve trailing newline if original had one — callers split on \n
    # which means an empty last element indicates a trailing newline.
    if lines and lines[-1] == "":
        # Already ends with empty string → the join produces trailing \n
        pass
    elif content and not content.endswith("\n"):
        content += "\n"
    _atomic_write(path, content)


# ---------------------------------------------------------------------------
# Callout insertion point
# ---------------------------------------------------------------------------

def _callout_insert_point(lines, section_start, section_end):
    """Return the line index where a NEW callout should be inserted.

    This is the first non-blank line after the section heading, skipping
    any blank lines immediately following the heading.
    """
    idx = section_start + 1
    # Skip blank lines immediately after the heading.
    while idx < section_end and lines[idx].strip() == "":
        idx += 1
    return idx


def _stale_insert_point(lines, section_start, section_end):
    """Return the line index where a STALE callout should be inserted.

    STALE goes right after the heading (after any blank lines).
    """
    return _callout_insert_point(lines, section_start, section_end)


def _draft_insert_point(lines, section_start, section_end):
    """Return the line index where a DRAFT callout should be inserted.

    Per D6 ordering: DRAFT goes AFTER any existing STALE callout.
    """
    # Check for existing STALE callout.
    stale_block = _find_callout_block(
        lines, section_start + 1, section_end, STALE_CALLOUT_RE
    )
    if stale_block is not None:
        _, stale_end = stale_block
        # Insert after the STALE block, skipping any blank line.
        idx = stale_end
        while idx < section_end and lines[idx].strip() == "":
            idx += 1
        return idx
    # No STALE callout — insert right after heading (after blank lines).
    return _callout_insert_point(lines, section_start, section_end)


# ---------------------------------------------------------------------------
# Public API — inject-stale
# ---------------------------------------------------------------------------

def inject_stale(file_path, section_name, reason_text, date=None):
    """Inject or append a [!STALE] reason into a section.

    - If the section has no [!STALE] callout, create one with reason (1).
    - If it already has reasons, append with the next number.
    - 3-reason cap: if a 4th reason arrives, drop the oldest (reason 1)
      and renumber remaining.
    - Date defaults to today.
    """
    if date is None:
        date = _today()

    content = _read_file(file_path)
    lines = content.split("\n")

    sec_start, sec_end, _ = _find_section(lines, section_name)

    # Look for existing STALE callout in this section.
    stale_block = _find_callout_block(
        lines, sec_start + 1, sec_end, STALE_CALLOUT_RE
    )

    if stale_block is None:
        # No existing STALE callout — create one.
        callout_line = (
            "> [!STALE] (1) %s (detected %s)." % (reason_text, date)
        )
        insert_idx = _stale_insert_point(lines, sec_start, sec_end)
        # Insert blank line before callout if needed (not right after heading).
        new_lines = []
        if insert_idx > sec_start + 1 and lines[insert_idx - 1].strip() != "":
            new_lines.append("")
        new_lines.append(callout_line)
        # Add blank line after if the next line is not blank and not EOF.
        if insert_idx < len(lines) and lines[insert_idx].strip() != "":
            new_lines.append("")
        for j, nl in enumerate(new_lines):
            lines.insert(insert_idx + j, nl)
    else:
        block_start, block_end = stale_block
        reasons = _parse_stale_reasons(lines, block_start, block_end)

        # Add the new reason.
        next_num = (reasons[-1][0] + 1) if reasons else 1
        reasons.append((next_num, reason_text, date))

        # 3-reason cap: drop oldest.
        while len(reasons) > MAX_STALE_REASONS:
            reasons.pop(0)

        # Renumber from 1.
        renumbered = []
        for i, (_, r_text, r_date) in enumerate(reasons, start=1):
            renumbered.append((i, r_text, r_date))

        # Build replacement callout lines.
        new_callout_lines = []
        for i, (num, r_text, r_date) in enumerate(renumbered):
            if i == 0:
                new_callout_lines.append(
                    "> [!STALE] (%d) %s (detected %s)."
                    % (num, r_text, r_date)
                )
            else:
                new_callout_lines.append(
                    "> (%d) %s (detected %s)." % (num, r_text, r_date)
                )

        # Replace the old callout block.
        lines[block_start:block_end] = new_callout_lines

    _write_lines(file_path, lines)


# ---------------------------------------------------------------------------
# Public API — remove-stale
# ---------------------------------------------------------------------------

def remove_stale(file_path, section_name):
    """Remove the entire [!STALE] callout block from a section."""
    content = _read_file(file_path)
    lines = content.split("\n")

    sec_start, sec_end, _ = _find_section(lines, section_name)

    stale_block = _find_callout_block(
        lines, sec_start + 1, sec_end, STALE_CALLOUT_RE
    )
    if stale_block is None:
        # Nothing to remove — idempotent success.
        return

    block_start, block_end = stale_block

    # Also remove a trailing blank line if the callout was followed by one.
    if block_end < len(lines) and lines[block_end].strip() == "":
        block_end += 1
    # Also remove a leading blank line if it was an empty line between
    # the heading and the callout.
    if block_start > 0 and lines[block_start - 1].strip() == "":
        block_start -= 1

    del lines[block_start:block_end]

    _write_lines(file_path, lines)


# ---------------------------------------------------------------------------
# Public API — inject-draft
# ---------------------------------------------------------------------------

def inject_draft(file_path, section_name, date=None):
    """Inject a [!DRAFT] callout into a section.

    If the section already has a [!DRAFT] callout, this is a no-op
    (idempotent).

    Per D6 ordering, DRAFT goes after any existing STALE callout.
    """
    if date is None:
        date = _today()

    content = _read_file(file_path)
    lines = content.split("\n")

    sec_start, sec_end, _ = _find_section(lines, section_name)

    # Check for existing DRAFT callout.
    draft_block = _find_callout_block(
        lines, sec_start + 1, sec_end, DRAFT_CALLOUT_RE
    )
    if draft_block is not None:
        # Already has a DRAFT callout — idempotent.
        return

    callout_line = (
        "> [!DRAFT] Agent-drafted content, not yet human-reviewed. "
        "(drafted %s)" % date
    )

    insert_idx = _draft_insert_point(lines, sec_start, sec_end)

    new_lines = []
    # Add blank line before if previous line is not blank and not the heading.
    if insert_idx > sec_start + 1 and lines[insert_idx - 1].strip() != "":
        new_lines.append("")
    new_lines.append(callout_line)
    # Add blank line after if the next line is not blank and not EOF.
    if insert_idx < len(lines) and lines[insert_idx].strip() != "":
        new_lines.append("")

    for j, nl in enumerate(new_lines):
        lines.insert(insert_idx + j, nl)

    _write_lines(file_path, lines)


# ---------------------------------------------------------------------------
# Public API — remove-draft
# ---------------------------------------------------------------------------

def remove_draft(file_path, section_name):
    """Remove the entire [!DRAFT] callout block from a section."""
    content = _read_file(file_path)
    lines = content.split("\n")

    sec_start, sec_end, _ = _find_section(lines, section_name)

    draft_block = _find_callout_block(
        lines, sec_start + 1, sec_end, DRAFT_CALLOUT_RE
    )
    if draft_block is None:
        # Nothing to remove — idempotent success.
        return

    block_start, block_end = draft_block

    # Also remove a trailing blank line if the callout was followed by one.
    if block_end < len(lines) and lines[block_end].strip() == "":
        block_end += 1
    # Also remove a leading blank line if it was an empty line between
    # the preceding content and the callout.
    if block_start > 0 and lines[block_start - 1].strip() == "":
        block_start -= 1

    del lines[block_start:block_end]

    _write_lines(file_path, lines)


# ---------------------------------------------------------------------------
# Public API — extract-links
# ---------------------------------------------------------------------------

# TODO: add path containment when Phase 4 CI gate ships (reject absolute
# paths, .. traversal, symlink escapes via realpath, URL-scheme links;
# anchor to git rev-parse --show-toplevel)

def extract_links(file_path, repo_root=None):
    """Extract all markdown links from a chapter file.

    Returns a list of repo-relative paths (compatible with
    ``git diff --name-only`` output). Skips non-existent targets
    and URL-scheme links.
    """
    if repo_root is None:
        # Default: walk up from the file to find .git.
        repo_root = _find_repo_root(file_path)
        if repo_root is None:
            raise ValueError(
                "cannot determine repo root; pass --repo-root explicitly"
            )

    repo_root = os.path.abspath(repo_root)
    chapter_dir = os.path.dirname(os.path.abspath(file_path))

    content = _read_file(file_path)
    results = []
    seen = set()

    for m in LINK_RE.finditer(content):
        target = m.group(1)

        # Skip URL-scheme links (http, https, ftp, mailto, file, etc.).
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", target) or target.startswith("mailto:"):
            continue

        # Strip fragment identifiers (#anchor).
        target = target.split("#")[0]
        if not target:
            continue

        # Resolve relative path from the chapter's directory.
        abs_target = os.path.normpath(os.path.join(chapter_dir, target))

        # Skip non-existent targets.
        if not os.path.exists(abs_target):
            continue

        # Convert to repo-relative path.
        try:
            rel_path = os.path.relpath(abs_target, repo_root)
        except ValueError:
            # Different drives on Windows — skip.
            continue

        if rel_path not in seen:
            seen.add(rel_path)
            results.append(rel_path)

    return results


def _find_repo_root(start_path):
    """Walk up from *start_path* looking for a .git directory."""
    current = os.path.abspath(start_path)
    if os.path.isfile(current):
        current = os.path.dirname(current)
    while True:
        if os.path.isdir(os.path.join(current, ".git")):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


# ---------------------------------------------------------------------------
# Public API — status
# ---------------------------------------------------------------------------

def status(file_path):
    """Report annotation counts for a Plot Document file.

    Returns a dict with keys: total, stale, draft, clean.
    """
    content = _read_file(file_path)
    lines = content.split("\n")

    sections = []
    for i, line in enumerate(lines):
        parsed = _parse_heading(line)
        if parsed is not None:
            sections.append((i, parsed[0], parsed[1]))

    total = len(sections)
    stale_count = 0
    draft_count = 0

    for idx, (sec_line, sec_level, sec_name) in enumerate(sections):
        # Determine section end.
        if idx + 1 < len(sections):
            sec_end = sections[idx + 1][0]
        else:
            sec_end = len(lines)

        has_stale = _find_callout_block(
            lines, sec_line + 1, sec_end, STALE_CALLOUT_RE
        ) is not None
        has_draft = _find_callout_block(
            lines, sec_line + 1, sec_end, DRAFT_CALLOUT_RE
        ) is not None

        if has_stale:
            stale_count += 1
        if has_draft:
            draft_count += 1

    # Clean = sections with neither stale nor draft.
    # Sections can have both annotations, so clean != total - stale - draft.
    both_count = 0
    for idx, (sec_line, sec_level, sec_name) in enumerate(sections):
        if idx + 1 < len(sections):
            sec_end = sections[idx + 1][0]
        else:
            sec_end = len(lines)
        has_stale = _find_callout_block(
            lines, sec_line + 1, sec_end, STALE_CALLOUT_RE
        ) is not None
        has_draft = _find_callout_block(
            lines, sec_line + 1, sec_end, DRAFT_CALLOUT_RE
        ) is not None
        if has_stale and has_draft:
            both_count += 1

    # A section is "annotated" if it has stale OR draft (or both).
    annotated = stale_count + draft_count - both_count
    clean = total - annotated

    return {
        "total": total,
        "stale": stale_count,
        "draft": draft_count,
        "clean": clean,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser():
    """Build the argparse parser with subcommands."""
    p = argparse.ArgumentParser(
        prog="scripts/_plot_annotations.py",
        description="Deterministic annotation helpers for Plot Document files.",
    )
    sub = p.add_subparsers(dest="command")

    # inject-stale
    sp = sub.add_parser("inject-stale", help="Inject a [!STALE] callout")
    sp.add_argument("--file", required=True, help="Path to the markdown file")
    sp.add_argument("--section", required=True, help="Section heading text")
    sp.add_argument("--reason", required=True, help="Reason text")
    sp.add_argument(
        "--date", default=None,
        help="Detection date (YYYY-MM-DD); defaults to today"
    )

    # remove-stale
    sp = sub.add_parser("remove-stale", help="Remove a [!STALE] callout")
    sp.add_argument("--file", required=True, help="Path to the markdown file")
    sp.add_argument("--section", required=True, help="Section heading text")

    # inject-draft
    sp = sub.add_parser("inject-draft", help="Inject a [!DRAFT] callout")
    sp.add_argument("--file", required=True, help="Path to the markdown file")
    sp.add_argument("--section", required=True, help="Section heading text")
    sp.add_argument(
        "--date", default=None,
        help="Draft date (YYYY-MM-DD); defaults to today"
    )

    # remove-draft
    sp = sub.add_parser("remove-draft", help="Remove a [!DRAFT] callout")
    sp.add_argument("--file", required=True, help="Path to the markdown file")
    sp.add_argument("--section", required=True, help="Section heading text")

    # extract-links
    sp = sub.add_parser("extract-links", help="Extract markdown links")
    sp.add_argument("--file", required=True, help="Path to the markdown file")
    sp.add_argument(
        "--repo-root", default=None,
        help="Repository root (auto-detected if omitted)"
    )

    # status
    sp = sub.add_parser("status", help="Report annotation counts")
    sp.add_argument("--file", required=True, help="Path to the markdown file")

    return p


def main(argv):
    """CLI entry point."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    if args.command == "inject-stale":
        inject_stale(args.file, args.section, args.reason, date=args.date)

    elif args.command == "remove-stale":
        remove_stale(args.file, args.section)

    elif args.command == "inject-draft":
        inject_draft(args.file, args.section, date=args.date)

    elif args.command == "remove-draft":
        remove_draft(args.file, args.section)

    elif args.command == "extract-links":
        links = extract_links(args.file, repo_root=args.repo_root)
        for link in links:
            sys.stdout.write(link + "\n")

    elif args.command == "status":
        st = status(args.file)
        sys.stdout.write("total: %d\n" % st["total"])
        sys.stdout.write("stale: %d\n" % st["stale"])
        sys.stdout.write("draft: %d\n" % st["draft"])
        sys.stdout.write("clean: %d\n" % st["clean"])

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
        sys.exit(0)
    except SystemExit:
        raise
    except ValueError as e:
        sys.stderr.write("error: %s\n" % e)
        sys.exit(1)
    except Exception as e:
        sys.stderr.write("error: %s\n" % e)
        sys.exit(1)
