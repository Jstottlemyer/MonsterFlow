"""Regression: Plot Markdown link extraction remains inside the repository."""
import tempfile
import unittest
from pathlib import Path

from scripts._plot_annotations import extract_links


class ExtractLinksContainmentTests(unittest.TestCase):
    def test_relative_internal_links_allowed_but_escapes_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            top = Path(temp)
            root = top / "repo"
            docs = root / "docs"
            docs.mkdir(parents=True)
            (root / "overview.md").write_text("internal")
            (docs / "scene.md").write_text("scene")
            (top / "secret.md").write_text("outside")
            (docs / "good-link").symlink_to(root / "overview.md")
            (docs / "bad-link").symlink_to(top / "secret.md")
            chapter = docs / "plot.md"
            chapter.write_text(
                "[parent](../overview.md) [same](scene.md#intro) "
                "[within](good-link) [escape](../../secret.md) "
                "[symlink](bad-link) [absolute](" + str(top / "secret.md") + ") "
                "[url](https://example.org/a) [scheme](file:../overview.md) "
                "[win](C:\\secret.md)"
            )
            self.assertEqual(
                extract_links(str(chapter), repo_root=str(root)),
                ["overview.md", "docs/scene.md"],
            )

    def test_outside_chapter_and_sibling_prefix_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            top = Path(temp)
            root = top / "repo"
            docs = root / "docs"
            docs.mkdir(parents=True)
            sibling = top / "repo-escape"
            sibling.mkdir()
            (sibling / "secret.md").write_text("secret")
            chapter = docs / "plot.md"
            chapter.write_text("[escape](../../repo-escape/secret.md)")
            self.assertEqual(extract_links(str(chapter), repo_root=str(root)), [])
            with self.assertRaisesRegex(ValueError, "outside repository root"):
                extract_links(str(sibling / "secret.md"), repo_root=str(root))


if __name__ == "__main__":
    unittest.main()
