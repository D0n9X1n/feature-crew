#!/usr/bin/env python3
"""Validate the bilingual wiki: separate English and Chinese Markdown pages.

Adapted from SonicTerm's scripts/check-wiki.py without its crate rules. Pages
come from the filesystem, the same top-level set the publisher copies, so the
checker also runs on scratch copies that have no Git metadata.

This is not a Markdown parser. It checks a restricted wiki dialect and rejects
some valid Markdown to keep its rules simple:

- Navigation counts only in two canonical forms: line 3, after a blank line 2,
  is exactly the language-switch link, labeled with the other language's name;
  and Home links each page at the start of a column-0 "- " bullet whose label
  is plain readable text.
- Code fences open and close at column 0; an indented fence-like line is an
  error, not a guess at container rules.
- HTML-like text ("<" before a letter, "!", "/", or "?") is rejected anywhere
  outside fenced blocks, inline code included.
- Link-shaped destinations are validated on every line, code examples
  included, so fence rules cannot hide a broken target.
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
# The destination after every "](", whatever the label holds. The lookahead
# consumes only "](", so overlapping candidates are each checked.
LINK_PATTERN = re.compile(r"\]\((?=([^)]+)\))")
# Block-quote and list markers that may open a line before a definition.
CONTAINER = r"(?:[ \t]|>|(?:[-+*]|[0-9]{1,9}[.)])[ \t])*"
# A reference definition at a line start after optional container markers. Its
# label may span lines and its destination may start on the next line. A label
# holds no unescaped bracket, so prose such as "[a][b]: text" is not one.
REFERENCE_PATTERN = re.compile(
    rf"^(?={CONTAINER}\[(?!\^)(?:[^\[\]\\]|\\.)*\]:[ \t]*(?:\n{CONTAINER})?([^ \t\n]+))",
    re.MULTILINE | re.DOTALL,
)
SPACE_RUN = re.compile(r"[ \t\n]+")
# The language-switch label names the other language.
SWITCH_LABEL_ON_ENGLISH_PAGE = "简体中文"
SWITCH_LABEL_ON_CHINESE_PAGE = "English"
# Home's link to a page opens a column-0 "- " bullet. Its label is plain
# readable text: at least one letter or digit, and no bracket, pipe, backslash,
# or backtick, any of which could stop it rendering as a link.
HOME_LINK_PATTERN = re.compile(r"- \[(?=[^\]]*[^\W_])[^\[\]|\\`]+\]\(([A-Za-z0-9-]+)\)")
# A fence opens at column 0; a backtick fence's info string holds no backtick.
FENCE_OPEN_PATTERN = re.compile(r"(`{3,})[^`]*$|(~{3,})")
INDENTED_FENCE_PATTERN = re.compile(r"[ \t]+(?:`{3}|~{3})")
RAW_HTML_PATTERN = re.compile(r"<[A-Za-z!/?]")
# CJK symbols and punctuation, ideographs, compatibility ideographs, full-width forms.
CJK_PATTERN = re.compile(r"[\u3000-\u303f\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]")
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
    """Yield (line number, line) for lines outside fenced code blocks.

    A fence opens at column 0 and closes only on a column-0 run of its own
    character at least as long as the opener, followed by nothing but
    whitespace. Indented fence-like lines are rejected separately.
    """
    fence = ""
    for number, line in enumerate(lines, start=1):
        if fence:
            if line.startswith(fence) and not line.lstrip(fence[0]).strip(" \t"):
                fence = ""
        elif opener := FENCE_OPEN_PATTERN.match(line):
            fence = opener.group(1) or opener.group(2)
        else:
            yield number, line


def heading_depths(lines: list[str]) -> list[int]:
    """Return heading depths outside fenced code blocks, in source order."""
    return [
        len(heading.group(1))
        for _, line in outside_fences(lines)
        if (heading := HEADING_PATTERN.match(line))
    ]


def blocks(lines: list[str]):
    """Yield (first line number, joined text) for each run of non-blank lines."""
    first, run = 0, []
    for number, line in enumerate(lines, start=1):
        if line.strip(" \t"):
            if not run:
                first = number
            run.append(line)
        elif run:
            yield first, "\n".join(run)
            run = []
    if run:
        yield first, "\n".join(run)


def link_targets(lines: list[str]) -> list[tuple[int, str]]:
    """Return every link-shaped destination with the line it starts on.

    Deliberately broad and fence-blind: the destination after every "](" and
    every reference definition count, code examples included. Labels and
    destinations may continue across lines within one block of non-blank lines.
    """
    links: list[tuple[int, str]] = []
    for first, text in blocks(lines):
        candidates = [
            (match.start(1), match.group(1))
            for pattern in (LINK_PATTERN, REFERENCE_PATTERN)
            for match in pattern.finditer(text)
        ]
        for offset, raw in candidates:
            leading = len(raw) - len(raw.lstrip(" \t\n"))
            destination = SPACE_RUN.sub(" ", raw).strip(" ")
            if destination.startswith("<") and destination.endswith(">"):
                destination = destination[1:-1]
            links.append((first + text.count("\n", 0, offset + leading), destination))
    return links


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


def switch_line(path: PurePosixPath, lines: list[str]) -> bool:
    """True when line 2 is blank and line 3, outside fences, is exactly the switch link."""
    if len(lines) < 3 or lines[1].strip(" \t"):
        return False
    if 3 not in {number for number, _ in outside_fences(lines)}:
        return False
    chinese = path.stem.endswith(CHINESE_SUFFIX)
    label = SWITCH_LABEL_ON_CHINESE_PAGE if chinese else SWITCH_LABEL_ON_ENGLISH_PAGE
    return lines[2] == f"[{label}]({counterpart_stem(path.stem)})"


def home_link_stems(lines: list[str]) -> set[str]:
    """Return the pages that Home links from the start of a column-0 bullet."""
    return {
        match.group(1)
        for _, line in outside_fences(lines)
        if (match := HOME_LINK_PATTERN.match(line))
    }


def validate_language(path: PurePosixPath, lines: list[str], switch_ok: bool, errors: list[str]) -> None:
    """English pages hold no Chinese beyond the switch line; Chinese pages hold Chinese."""
    body = [(number, line) for number, line in enumerate(lines, start=1) if not (switch_ok and number == 3)]
    if path.stem.endswith(CHINESE_SUFFIX):
        if not any(CJK_PATTERN.search(line) for _, line in body):
            errors.append(f"{path}: no Chinese text in a Chinese page")
        return
    for number, line in body:
        if CJK_PATTERN.search(line):
            errors.append(f"{path}:{number}: Chinese text in an English page")


def main() -> int:
    """Validate pairing, structure, links, language, and navigation."""
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
        switch_ok = switch_line(path, lines)
        if not switch_ok:
            errors.append(f"{path}: missing language-switch link to {counterpart} on line 3")
        for number, line in enumerate(lines, start=1):
            if INDENTED_FENCE_PATTERN.match(line):
                errors.append(f"{path}:{number}: code fences must start at column 0")
        for number, line in outside_fences(lines):
            if RAW_HTML_PATTERN.search(line):
                errors.append(f"{path}:{number}: raw HTML is not allowed")
        validate_links(path, lines, page_stems, errors)
        validate_language(path, lines, switch_ok, errors)

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
        for stem in sorted(same_language - {home.stem} - home_link_stems(lines_by_path[home])):
            errors.append(f"{home}: missing link to {stem}")

    if errors:
        for error in sorted(errors):
            print(f"check-wiki: {error}", file=sys.stderr)
        return 1
    print(f"check-wiki: ok ({len(pages)} pages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
