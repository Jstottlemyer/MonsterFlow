#!/usr/bin/env python3
"""
_replace_sentinel_block.py — Atomic sentinel-block replacement for text files.

Standalone utility (NOT a heredoc/stdin script) per the hook-stdin-heredoc pattern:
running `python3 - <<'PY'` occupies stdin, so JSON-piped input never arrives.
This file is invoked as a real script by install.sh wrappers.

Usage (CLI):
    python3 _replace_sentinel_block.py <target_file> <start_sentinel> <end_sentinel> \\
        [--backup <path>] \\
        (--stdin-content | --content-file <path>)

    Prints one line to stdout:
        replaced   — existing sentinel block was found and content was changed
        appended   — no existing sentinels; new block appended to end of file
        unchanged  — sentinels found; content already matches; no write performed

Exit codes:
    0 — success (replaced / appended / unchanged)
    1 — misuse (missing args, both content sources provided, etc.)
    2 — filesystem error (I/O failure, permission denied, etc.)

Library use:
    from _replace_sentinel_block import replace_block
    result = replace_block(
        target_file="/path/to/file",
        start_sentinel="<!-- WIKI-CONVENTIONS-START -->",
        end_sentinel="<!-- WIKI-CONVENTIONS-END -->",
        new_content="...block content...",
        backup_path="/path/to/backup",   # optional
    )
    # result is one of: "replaced", "appended", "unchanged"
"""

import argparse
import os
import shutil
import sys
import tempfile
from typing import Optional


# ---------------------------------------------------------------------------
# Core library function
# ---------------------------------------------------------------------------

def replace_block(
    target_file: str,
    start_sentinel: str,
    end_sentinel: str,
    new_content: str,
    backup_path: Optional[str] = None,
) -> str:
    """Replace or append a sentinel-delimited block in *target_file*.

    Behaviour:
    - If the file does not exist OR the sentinels are not present:
      APPEND a new block at the end of the file (with a leading blank line)
      in the form::

          <blank line>
          <start_sentinel>
          <new_content>
          <end_sentinel>

    - If both sentinels are present: REPLACE the lines between them with
      *new_content*. The sentinel lines themselves are preserved verbatim.

    - Idempotent: if the content between sentinels already exactly matches
      *new_content*, no write is performed and no backup is created.

    - Atomic write via ``tempfile.NamedTemporaryFile(dir=<target_dir>,
      delete=False)`` + ``os.replace``.

    - If *backup_path* is given AND *target_file* already exists, the original
      is copied to *backup_path* BEFORE the atomic write.

    Returns one of: ``"replaced"``, ``"appended"``, ``"unchanged"``.

    Raises ``OSError`` on filesystem errors.
    """
    target_file = os.path.expanduser(target_file)
    target_dir = os.path.dirname(os.path.abspath(target_file))

    # ------------------------------------------------------------------
    # Read existing content (if file exists)
    # ------------------------------------------------------------------
    if os.path.exists(target_file):
        with open(target_file, "r", encoding="utf-8") as fh:
            original_text = fh.read()
        file_existed = True
    else:
        original_text = ""
        file_existed = False

    # ------------------------------------------------------------------
    # Locate sentinels
    # ------------------------------------------------------------------
    start_idx = original_text.find(start_sentinel)
    end_idx = original_text.find(end_sentinel)
    sentinels_present = (start_idx != -1 and end_idx != -1 and start_idx < end_idx)

    if sentinels_present:
        # Extract current block content (text between the sentinel lines)
        # start_sentinel is on its own line; find the newline after it.
        after_start = start_idx + len(start_sentinel)
        # Skip the newline that terminates the start-sentinel line
        if after_start < len(original_text) and original_text[after_start] == "\n":
            after_start += 1
        current_content = original_text[after_start:end_idx]
        # Strip trailing newline that sits immediately before end_sentinel
        if current_content.endswith("\n"):
            current_content = current_content[:-1]

        if current_content == new_content:
            return "unchanged"

        # Build new text: pre-block + start_sentinel + content + end_sentinel + post-block
        before_start = original_text[:start_idx]
        # end_idx points to start of end_sentinel line
        after_end = end_idx + len(end_sentinel)
        after_block = original_text[after_end:]

        new_text = (
            before_start
            + start_sentinel
            + "\n"
            + new_content
            + "\n"
            + end_sentinel
            + after_block
        )
        action = "replaced"
    else:
        # Append mode
        leading = "\n" if original_text and not original_text.endswith("\n\n") else ""
        if original_text and not original_text.endswith("\n"):
            leading = "\n" + leading  # ensure we start on a new line

        new_text = (
            original_text
            + leading
            + "\n"
            + start_sentinel
            + "\n"
            + new_content
            + "\n"
            + end_sentinel
            + "\n"
        )
        action = "appended"

    # ------------------------------------------------------------------
    # Backup (before any write)
    # ------------------------------------------------------------------
    if backup_path is not None and file_existed:
        backup_path_expanded = os.path.expanduser(backup_path)
        shutil.copy2(target_file, backup_path_expanded)

    # ------------------------------------------------------------------
    # Atomic write
    # ------------------------------------------------------------------
    os.makedirs(target_dir, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=target_dir)
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as tmp_fh:
            tmp_fh.write(new_text)
        os.replace(tmp_path, target_file)
    except Exception:
        # Clean up orphaned temp file if rename failed
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    return action


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Atomically replace or append a sentinel-delimited block in a text file."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Prints one of: replaced | appended | unchanged\n"
            "Exit codes: 0=success, 1=misuse, 2=filesystem error"
        ),
    )
    parser.add_argument("target_file", help="Path to the file to update")
    parser.add_argument("start_sentinel", help="Opening sentinel string (exact match)")
    parser.add_argument("end_sentinel", help="Closing sentinel string (exact match)")
    parser.add_argument(
        "--backup",
        metavar="PATH",
        help="Copy target_file to PATH before writing (only if file already exists)",
    )
    content_group = parser.add_mutually_exclusive_group(required=True)
    content_group.add_argument(
        "--stdin-content",
        action="store_true",
        help="Read new block content from stdin",
    )
    content_group.add_argument(
        "--content-file",
        metavar="PATH",
        help="Read new block content from this file",
    )
    return parser


def main(argv: Optional[list] = None) -> int:
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        # argparse calls sys.exit(2) on bad args; remap to exit 1 per spec
        return 1

    # Read content
    if args.stdin_content:
        new_content = sys.stdin.read()
        # Strip exactly one trailing newline if present (sentinel block content
        # should not carry a gratuitous trailing newline; replace_block adds one)
        if new_content.endswith("\n"):
            new_content = new_content[:-1]
    else:
        content_path = os.path.expanduser(args.content_file)
        try:
            with open(content_path, "r", encoding="utf-8") as fh:
                new_content = fh.read()
            if new_content.endswith("\n"):
                new_content = new_content[:-1]
        except OSError as exc:
            print(
                "error: cannot read content-file {!r}: {}".format(content_path, exc),
                file=sys.stderr,
            )
            return 2

    try:
        result = replace_block(
            target_file=args.target_file,
            start_sentinel=args.start_sentinel,
            end_sentinel=args.end_sentinel,
            new_content=new_content,
            backup_path=args.backup if args.backup else None,
        )
    except OSError as exc:
        print("error: filesystem error: {}".format(exc), file=sys.stderr)
        return 2

    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
