#!/usr/bin/env python3
"""
_tag_baseline.py — baseline tag computation for tags_provenance (SEC-04).

Pure helper invoked by the resolver and by the CLI. Re-derives the set of
baseline tags implied by a spec's prose using a fixed keyword regex map.
Used by assert_baseline_subset() to detect post-write shrinking attacks
(recomputed baseline must remain a subset of recorded baseline; if the
resolver re-discovers a keyword the recorded list doesn't acknowledge,
the recorded list was shrunk to evade dispatch).

Pipeline (NORMATIVE ORDER):
  1. NFKC normalize + strip zero-width chars
  2. Strip leading YAML frontmatter (--- ... ---) — before fence-strip so a
     frontmatter `tags: [security]` cannot self-trigger detection (plan G7)
  3. Strip balanced ```fenced``` code blocks (MULTILINE+DOTALL); unbalanced
     fences leave content intact (full scan)
  4. Lowercase
  5. Apply BASELINE_KEYWORDS regex map (case-insensitive)
  6. Return set[str] of matched tag names

CLI:
  python3 scripts/_tag_baseline.py <spec_file>
  stdout: {"baseline": [...sorted]}
  exit 0 ok, 2 read error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

BASELINE_KEYWORDS: dict[str, str] = {
    "security":    r"(?<!\w)(auth|secret|token|rbac|threat|pii|oauth|credential|cve|injection|permission|session|signing|key[-_ ]rotation|sev:security|tier_policy|tier_pins|password|api[-_ ]key|sql[-_ ]injection|csrf|xss|rce|untrusted[-_ ]input|escape[-_ ]hatch|downgrade|bypass|attack|vuln|exfiltrat|adversari|prompt[-_ ]injection)(?!\w)",
    "data":        r"(?<!\w)(schema|migration|jsonl|sqlite|database|atomic[-_ ]write|fcntl|flock|persisted)(?!\w)",
    "api":         r"(?<!\w)(--[a-z][a-z0-9-]+|cli|flag|subcommand|env(?:ironment)?[-_ ]variable|stdout|stderr|exit[-_ ]code)(?!\w)",
    "ux":          r"(?<!\w)(prompt|approval[-_ ]gate|user[-_ ]flow|confirm|interactive|q&a)(?!\w)",
    "integration": r"(?<!\w)(hook|wrapper|symlink|install\.sh|gate|dispatch[-_ ]path)(?!\w)",
    "scalability": r"(?<!\w)(parallel|wave|race|cold[-_ ]start|backoff|retry|timeout|rate[-_ ]limit)(?!\w)",
    "migration":   r"(?<!\w)(symlink|backfill|deprecation|back[-_ ]compat|legacy[-_ ]fallback)(?!\w)",
}

# Cyrillic→Latin homoglyph map. NFKC alone does NOT map U+0430 ('а') to
# U+0061 ('a') — they are distinct canonical codepoints, not compatibility-
# equivalent. Spec SEC-02 + Edge Case 22 require this bypass to be closed,
# so we apply an explicit confusables map after NFKC. Covers the lowercase
# Cyrillic letters that visually collide with ASCII a-z.
_CYRILLIC_TO_LATIN = str.maketrans({
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "А": "A", "Е": "E", "О": "O", "Р": "P", "С": "C", "У": "Y", "Х": "X",
    "і": "i", "І": "I", "ј": "j", "Ј": "J", "ѕ": "s", "Ѕ": "S",
    "к": "k", "К": "K", "т": "t", "Т": "T", "в": "B", "н": "H", "м": "M",
})

_ZERO_WIDTH = re.compile(r"[​‌‍⁠﻿]")
_FRONTMATTER = re.compile(r"\A---\n.*?\n---\n", re.DOTALL)
_FENCE = re.compile(r"`{3,}[^\n]*\n.*?\n`{3,}", re.DOTALL | re.MULTILINE)
_FENCE_COUNT = re.compile(r"^`{3,}", re.MULTILINE)

_COMPILED = {tag: re.compile(pat, re.IGNORECASE) for tag, pat in BASELINE_KEYWORDS.items()}


class TagDriftError(Exception):
    """Raised when recomputed baseline is not a subset of recorded baseline."""


def _preprocess(spec_text: str) -> str:
    """Steps 1-4: normalize, strip frontmatter, strip balanced fences, lowercase."""
    text = unicodedata.normalize("NFKC", spec_text)
    text = text.translate(_CYRILLIC_TO_LATIN)
    text = _ZERO_WIDTH.sub("", text)
    text = _FRONTMATTER.sub("", text, count=1)
    # Only strip fences when the count of ``` markers is even (balanced).
    fence_markers = _FENCE_COUNT.findall(text)
    if len(fence_markers) % 2 == 0:
        text = _FENCE.sub("", text)
    return text.lower()


def compute_baseline(spec_text: str) -> set[str]:
    """Run the 6-step pipeline; return matched tag names."""
    body = _preprocess(spec_text)
    matched: set[str] = set()
    for tag, rx in _COMPILED.items():
        if rx.search(body):
            matched.add(tag)
    return matched


def assert_baseline_subset(recorded, spec_file) -> None:
    """Assert compute_baseline(spec_file) is a subset of set(recorded).

    SEC-04 attack model: an attacker writes spec content with security keywords
    then post-write shrinks `tags_provenance.baseline` to evade dispatch of
    security personas. Detection: every keyword the resolver re-discovers
    must already appear in the recorded baseline. If `recomputed - recorded`
    is non-empty, the recorded list was shrunk relative to current content.

    The opposite direction (recorded ⊋ recomputed; author legitimately
    removed content that previously baselined) is the resolver's
    responsibility — it warns and proceeds (D8 mid-pipeline-edit clause).
    """
    path = Path(spec_file)
    spec_text = path.read_text(encoding="utf-8")
    recomputed = compute_baseline(spec_text)
    recorded_set = set(recorded)
    if not recomputed.issubset(recorded_set):
        rec_sorted = sorted(recorded_set)
        recom_sorted = sorted(recomputed)
        raise TagDriftError(
            "[tier-policy] SEC-04: tags_provenance.baseline drift detected; "
            "refusing to dispatch\n"
            f"  recorded={rec_sorted}; recomputed={recom_sorted}"
        )


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Compute baseline tags from a spec file.")
    parser.add_argument("spec_file", help="Path to spec markdown file")
    args = parser.parse_args(argv)
    try:
        text = Path(args.spec_file).read_text(encoding="utf-8")
    except (FileNotFoundError, OSError, UnicodeDecodeError) as e:
        print(f"error: cannot read {args.spec_file}: {e}", file=sys.stderr)
        return 2
    baseline = compute_baseline(text)
    json.dump({"baseline": sorted(baseline)}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
