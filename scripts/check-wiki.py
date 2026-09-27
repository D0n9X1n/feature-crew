#!/usr/bin/env python3
"""Validate the bilingual wiki: separate English and Chinese Markdown pages.

Adapted from SonicTerm's scripts/check-wiki.py without its crate rules. Pages
come from the filesystem, the same top-level set the publisher copies, so the
checker also runs on scratch copies that have no Git metadata.
"""

from __future__ import annotations

from pathlib import Path, PurePosixPath
import re
import sys
from urllib.parse import unquote, urlsplit

CHINESE_SUFFIX = "-zh-CN"
LEGACY_MARKERS = frozenset({"## English", "## 中文"})
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*$")
HEADING_PATTERN = re.compile(r"^(#{1,6})[ \t]+")
LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
REFERENCE_PATTERN = re.compile(r"^[ \t]{0,3}\[(?!\^)[^\]]+\]:[ \t]*(\S+)")
FENCE_PATTERN = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})")
# CJK symbols and punctuation, ideographs, compatibility ideographs, full-width forms.
CJK_PATTERN = re.compile("[　-〿㐀-䶿一-鿿豈-﫿＀-￯]")
EXTERNAL_SCHEMES = frozenset(
    {"data", "ftp", "ftps", "http", "https", "irc", "ircs", "mailto", "news", "ssh", "tel"}
)


def repository_root() -> Path:
    """Return the repository root containing this checker."""
    return Path(__file__).resolve().parent.parent


def counterpart_stem(stem: str) -> str:
    """Return the other-language page name."""
    return stem.removesuffix(CHINESE_SUFFIX) if stem.endswith(CHINESE_SUFFIX) else stem + CHINESE_SUFFIX


def outside_fences(lines: list[str]):
    """Yield (line number, line) for lines outside fenced code blocks."""
    fence: str | None = None
    fence_length = 0
    for number, line in enumerate(lines, start=1):
        marker = FENCE_PATTERN.match(line)
        if marker:
            run = marker.group(1)
            if fence is None:
                fence, fence_length = run[0], len(run)
            elif run[0] == fence and len(run) >= fence_length:
                fence, fence_length = None, 0
            continue
        if fence is None:
            yield number, line


def heading_depths(lines: list[str]) -> list[int]:
    """Return heading depths outside fenced code blocks, in source order."""
    return [
        len(heading.group(1))
        for _, line in outside_fences(lines)
        if (heading := HEADING_PATTERN.match(line))
    ]


def link_targets(lines: list[str], definitions: bool = True) -> list[tuple[int, str]]:
    """Return link destinations outside fenced code blocks.

    Inline links always count; reference definitions count only when
    `definitions` is true, because a definition alone renders no link.
    """
    links: list[tuple[int, str]] = []
    for number, line in outside_fences(lines):
        destinations = [match.group(1) for match in LINK_PATTERN.finditer(line)]
        if definitions and (reference := REFERENCE_PATTERN.match(line)):
            destinations.append(reference.group(1))
        for destination in destinations:
            destination = destination.strip()
            if destination.startswith("<") and destination.endswith(">"):
                destination = destination[1:-1].strip()
            links.append((number, destination))
    return links


def local_link_stems(lines: list[str]) -> set[str]:
    """Return page names that inline links navigate to, excluding URLs and same-page anchors.

    Reference definitions are validated elsewhere but never count as navigation:
    the language switch and Home links must be inline links.
    """
    linked: set[str] = set()
    for _, target in link_targets(lines, definitions=False):
        parsed = urlsplit(unquote(target))
        if target.startswith("#") or parsed.scheme or parsed.netloc:
            continue
        linked.add(parsed.path)
    return linked


def validate_links(path: PurePosixPath, lines: list[str], page_stems: set[str], errors: list[str]) -> None:
    """Page links name existing pages, omit .md, and stay in one language."""
    for number, raw_target in link_targets(lines):
        target = unquote(raw_target)
        if target.startswith("#"):
            continue
        parsed = urlsplit(target)
        if parsed.scheme.lower() in EXTERNAL_SCHEMES or parsed.netloc:
            continue
        page = parsed.path
        if page.endswith(".md"):
            errors.append(f"{path}:{number}: cross-page link must omit .md: {raw_target}")
        elif page not in page_stems:
            errors.append(f"{path}:{number}: cross-page link target does not exist: {raw_target}")
        elif page != counterpart_stem(path.stem) and page.endswith(CHINESE_SUFFIX) != path.stem.endswith(CHINESE_SUFFIX):
            errors.append(f"{path}:{number}: cross-page link must stay in the same language: {raw_target}")


def validate_language(path: PurePosixPath, lines: list[str], errors: list[str]) -> None:
    """English pages hold no Chinese beyond the switch link; Chinese pages hold Chinese."""
    switch = re.compile(r"\[[^\]]*\]\(" + re.escape(counterpart_stem(path.stem)) + r"\)")
    if path.stem.endswith(CHINESE_SUFFIX):
        if not any(CJK_PATTERN.search(switch.sub("", line)) for line in lines):
            errors.append(f"{path}: no Chinese text in a Chinese page")
        return
    for number, line in enumerate(lines, start=1):
        if CJK_PATTERN.search(switch.sub("", line)):
            errors.append(f"{path}:{number}: Chinese text in an English page")


def main() -> int:
    """Validate pairing, structure, links, language, and Home navigation."""
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    wiki = repository_root() / "wiki"
    if not wiki.is_dir():
        print("check-wiki: wiki/ does not exist", file=sys.stderr)
        return 1
    errors: list[str] = []
    for nested in sorted(p for p in wiki.rglob("*.md") if p.parent != wiki):
        errors.append(f"wiki/{nested.relative_to(wiki).as_posix()}: nested Markdown pages are not allowed")
    pages = sorted(PurePosixPath("wiki", p.name) for p in wiki.glob("*.md") if p.is_file())
    if not pages:
        errors.append("wiki: no Markdown pages found")
    page_stems = {path.stem for path in pages}
    lines_by_path: dict[PurePosixPath, list[str]] = {}
    for path in pages:
        if not NAME_PATTERN.match(path.stem):
            errors.append(f"{path}: page files need a flat ASCII name")
        lines = (wiki / path.name).read_text(encoding="utf-8").splitlines()
        lines_by_path[path] = lines
        if not lines or not lines[0].startswith("# "):
            errors.append(f"{path}: page does not start with a title")
        for marker in sorted(LEGACY_MARKERS.intersection(lines)):
            errors.append(f"{path}: legacy language marker {marker!r}; use separate files")
        counterpart = counterpart_stem(path.stem)
        if counterpart not in page_stems:
            errors.append(f"{path}: missing language counterpart: {counterpart}")
        if counterpart not in local_link_stems(lines):
            errors.append(f"{path}: missing language-switch link to {counterpart}")
        validate_links(path, lines, page_stems, errors)
        validate_language(path, lines, errors)

    for path, english_lines in lines_by_path.items():
        if path.stem.endswith(CHINESE_SUFFIX):
            continue
        chinese_path = path.with_stem(counterpart_stem(path.stem))
        if chinese_path not in lines_by_path:
            continue
        english_depths = heading_depths(english_lines)
        chinese_depths = heading_depths(lines_by_path[chinese_path])
        if english_depths != chinese_depths:
            errors.append(
                f"{path}: heading-depth sequences differ from {chinese_path}: "
                f"English {english_depths}; Chinese {chinese_depths}"
            )

    for suffix in ("", CHINESE_SUFFIX):
        home = PurePosixPath(f"wiki/Home{suffix}.md")
        if home not in lines_by_path:
            errors.append(f"{home}: required page is missing")
            continue
        same_language = {stem for stem in page_stems if stem.endswith(CHINESE_SUFFIX) == bool(suffix)}
        for stem in sorted(same_language - {home.stem} - local_link_stems(lines_by_path[home])):
            errors.append(f"{home}: missing link to {stem}")

    if errors:
        for error in sorted(errors):
            print(f"check-wiki: {error}", file=sys.stderr)
        return 1
    print(f"check-wiki: ok ({len(pages)} pages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
