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

    def test_auto_detects_worktree_gitfile_and_contains_links(self):
        # Linked worktrees use a .git pointer file, not a .git directory.
        with tempfile.TemporaryDirectory() as temp:
            top = Path(temp)
            root = top / "worktree"
            docs = root / "docs"
            docs.mkdir(parents=True)
            (root / ".git").write_text("gitdir: ../common/.git/worktrees/worktree\n")
            (root / "overview.md").write_text("inside")
            (top / "secret.md").write_text("outside")
            chapter = docs / "plot.md"
            chapter.write_text("[inside](../overview.md) [escape](../../secret.md)")
            self.assertEqual(extract_links(str(chapter)), ["overview.md"])

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


    def test_link_extraction_ignores_inline_code_examples(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ("example.md", "real.md"):
                (root / name).write_text(name)
            chapter = root / "plot.md"
            chapter.write_text(
                "`[inline](example.md)` [real](real.md)\n"
                "``[long](example.md)``\n"
                "`[multiline](example.md)\ncontinued`\n"
            )
            self.assertEqual(
                extract_links(str(chapter), repo_root=str(root)),
                ["real.md"],
            )

    def test_escaped_open_bracket_is_not_a_link(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "example.md").write_text("example")
            (root / "real.md").write_text("real")
            chapter = root / "plot.md"
            for markdown, expected in (
                (r"\[literal](example.md) [real](real.md)", ["real.md"]),
                (r"\\[valid](example.md) [real](real.md)", ["example.md", "real.md"]),
            ):
                with self.subTest(markdown=markdown):
                    chapter.write_text(markdown)
                    self.assertEqual(
                        extract_links(str(chapter), repo_root=str(root)), expected,
                    )

    def test_link_extraction_ignores_fenced_markdown_examples(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            docs = root / "docs"
            docs.mkdir(parents=True)
            for name in ("inside.md", "example.md", "after.md"):
                (docs / name).write_text(name)
            chapter = docs / "plot.md"
            chapter.write_text(
                "[before](inside.md)\n"
                "```md\n[example](example.md)\n```\n"
                "[after](after.md)\n"
                "~~~txt\n[another example](example.md)\n~~~\n"
            )
            self.assertEqual(
                extract_links(str(chapter), repo_root=str(root)),
                ["docs/inside.md", "docs/after.md"],
            )


    def test_quoted_markdown_titles_are_not_part_of_local_paths(self):
        # Standard Markdown link titles must not be interpreted as filenames.
        with tempfile.TemporaryDirectory() as temp:
            top = Path(temp)
            root = top / "repo"
            root.mkdir()
            (root / "scene.md").write_text("inside")
            (top / "secret.md").write_text("outside")
            chapter = root / "plot.md"
            chapter.write_text(
                "[double](scene.md \"Scene #1\") "
                "[single](scene.md 'another title') "
                "[escape](../secret.md \"outside\") "
                "[url](https://example.org/scene \"remote\") "
                "`[code](scene.md "not a link")`"
            )
            self.assertEqual(extract_links(str(chapter), repo_root=str(root)), ["scene.md"])


if __name__ == "__main__":
    unittest.main()
