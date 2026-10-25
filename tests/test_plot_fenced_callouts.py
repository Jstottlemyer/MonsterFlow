"""Regression: Plot annotation operations must ignore fenced example callouts."""
import tempfile
import unittest
from pathlib import Path

from scripts._plot_annotations import inject_stale, remove_stale


class FencedCalloutTests(unittest.TestCase):
    def test_inject_and_remove_preserve_fenced_example(self):
        original = ("# Plot\n## Scene\n\n```md\n"
                    "> [!STALE] (1) sample (detected 2025-01-01).\n"
                    "```\n\nStory.\n")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "plot.md"
            path.write_text(original, encoding="utf-8")
            inject_stale(str(path), "Scene", "real", date="2026-10-25")
            updated = path.read_text(encoding="utf-8")
            self.assertEqual(updated.count("[!STALE]"), 2)
            self.assertIn("> [!STALE] (1) real", updated)
            remove_stale(str(path), "Scene")
            restored = path.read_text(encoding="utf-8")
            self.assertNotIn("> [!STALE] (1) real", restored)
            self.assertIn("> [!STALE] (1) sample", restored)

    def test_remove_skips_fenced_example_before_live_callout(self):
        original = ("# Plot\n## Scene\n\n~~~md\n"
                    "> [!STALE] (1) example (detected 2025-01-01).\n"
                    "~~~\n\n> [!STALE] (1) real (detected 2026-10-25).\n\nText.\n")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "plot.md"
            path.write_text(original, encoding="utf-8")
            remove_stale(str(path), "Scene")
            current = path.read_text(encoding="utf-8")
            self.assertIn("> [!STALE] (1) example", current)
            self.assertNotIn("> [!STALE] (1) real", current)


if __name__ == "__main__":
    unittest.main()
