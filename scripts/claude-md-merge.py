#!/usr/bin/env python3
"""claude-md-merge.py — diff ~/CLAUDE.md against the template and offer to add missing
canonical sections (behavioral rules, not personal stubs).

Usage: python3 scripts/claude-md-merge.py [--target PATH] [--template PATH]
"""
from __future__ import annotations

import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_DIR = SCRIPT_DIR.parent
DEFAULT_TEMPLATE = REPO_DIR / "templates" / "CLAUDE.md"
DEFAULT_TARGET = Path.home() / "CLAUDE.md"

# Sections that are behavioral rules, not personal stubs — worth pulling in.
CANONICAL = [
    "## Workflow Pipeline",
    "## Secrets Handling",
    "## Plugins & Skills",
    "## Collaboration Preferences",
    "## Output Verbosity",
    "## Verify Before Shipping",
    "## Instruction Adherence",
]


def parse_sections(path: Path) -> dict:
    """Return {heading: full_block_text} for every ## section."""
    sections: dict = {}
    current_heading: str | None = None
    current_lines: list = []

    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            if current_heading is not None:
                sections[current_heading] = "\n".join(current_lines).strip()
            current_heading = line.rstrip()
            current_lines = [line]
        else:
            if current_heading is not None:
                current_lines.append(line)

    if current_heading is not None:
        sections[current_heading] = "\n".join(current_lines).strip()

    return sections


def _first_content_line(block: str) -> str:
    for line in block.splitlines()[1:]:
        stripped = line.strip()
        if stripped and not stripped.startswith("<!--"):
            return stripped[:90]
    return ""


def main(argv: list = sys.argv[1:]) -> int:
    template_path = DEFAULT_TEMPLATE
    target_path = DEFAULT_TARGET

    i = 0
    while i < len(argv):
        if argv[i] == "--template" and i + 1 < len(argv):
            template_path = Path(argv[i + 1])
            i += 2
        elif argv[i] == "--target" and i + 1 < len(argv):
            target_path = Path(argv[i + 1])
            i += 2
        else:
            i += 1

    if not template_path.exists():
        print(f"Template not found: {template_path}", file=sys.stderr)
        return 1
    if not target_path.exists():
        print(f"{target_path} not found — run install.sh to copy the baseline.")
        return 0

    template_sections = parse_sections(template_path)
    target_sections = parse_sections(target_path)

    target_headings_lower = {h.lower() for h in target_sections}
    missing = [h for h in CANONICAL if h.lower() not in target_headings_lower]

    if not missing:
        print(f"{target_path} is up to date — all canonical sections present.")
        return 0

    print(f"\nSections in templates/CLAUDE.md not found in {target_path}:\n")
    for idx, heading in enumerate(missing, 1):
        preview = _first_content_line(template_sections.get(heading, ""))
        print(f"  {idx}. {heading}")
        if preview:
            print(f"     {preview}")

    print()
    try:
        choice = input("Add missing sections? [all / 1,2,3 / skip]: ").strip().lower()
    except EOFError:
        print("(non-interactive — skipping)")
        return 0

    if not choice or choice in ("skip", "n", "no", "s"):
        print("Skipped.")
        return 0

    if choice == "all":
        to_add = missing
    else:
        try:
            indices = [int(x.strip()) - 1 for x in choice.split(",")]
            to_add = [missing[j] for j in indices if 0 <= j < len(missing)]
        except (ValueError, IndexError):
            print("Invalid input — skipping.")
            return 0

    if not to_add:
        print("Nothing selected.")
        return 0

    # Wrap appended content in sentinel pair so uninstall.sh can strip it
    # cleanly (uninstall-sh spec D8 — sentinel ownership lives here per
    # install-sh-claude-md-ownership prereq carve-off, MVP subset).
    SENTINEL_BEGIN = "# BEGIN MonsterFlow CLAUDE.md baseline"
    SENTINEL_END = "# END MonsterFlow CLAUDE.md baseline"

    existing_text = target_path.read_text(encoding="utf-8")
    already_bracketed = SENTINEL_BEGIN in existing_text and SENTINEL_END in existing_text

    with open(target_path, "a", encoding="utf-8") as f:
        if not already_bracketed:
            f.write(f"\n{SENTINEL_BEGIN}\n")
        for heading in to_add:
            content = template_sections.get(heading, "")
            f.write(f"\n{content}\n")
        if not already_bracketed:
            f.write(f"\n{SENTINEL_END}\n")

    print(f"\nAdded {len(to_add)} section(s) to {target_path}:")
    for h in to_add:
        print(f"  + {h}")
    if not already_bracketed:
        print(f"  (wrapped in '{SENTINEL_BEGIN}' / '{SENTINEL_END}' sentinels for uninstall reversibility)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
