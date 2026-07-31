#!/usr/bin/env python3
"""Verify every symbol anchor in `docs/design/SCREEN_SPECS.md` against the source.

The spec points at source code by *symbol name*, never by line number, because
line numbers go stale on every edit while names do not.  The canonical form is::

    `app/lib/ride/passenger_ride_page.dart` → `_LocationStep`

This script discovers those (file, symbol) pairs **by parsing the spec itself** --
there is no hand-maintained list to keep in sync -- and checks that each file
exists and that each symbol really occurs in it.

Two anchor shapes are collected:

1. An explicit arrow pair anywhere in the document, including ``/``-separated
   runs such as ``… → `TariffStore` / `SharedPreferencesTariffStore` ``.
2. The bare symbols inside a ``**Файл:**`` block, attributed to the most recent
   path named in that block (a block ends at the first blank line).

Non-Dart targets (``.yaml``, ``.html``) are checked too: the last dotted
component of the token (``flutter_native_splash.color_dark`` -> ``color_dark``,
``#status`` -> ``status``) must appear in the file.

On top of resolving anchors the script also *forbids the shape it replaced*: any
code span that points at a `file.ext:NN` line number fails the run.  Checking
only the symbol anchors let two stragglers survive the migration (they named
``app_mn.arb``, an extension this script does not resolve, so nothing looked at
them).  A ban is extension-agnostic and cannot miss one.  Documented "before"
examples are exempt by being written inside a double-backtick span, which is how
Хавсралт Б.3's before/after table already quotes them.

Usage::

    python tools/check_spec_symbols.py              # check the default spec
    python tools/check_spec_symbols.py path/to.md   # check another document

Exit status is 0 when every pair resolves (a one-line count is printed) and 1
when any does not, with one ``FAIL`` line per unresolved pair naming the file,
the symbol and the spec line it came from.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Iterator, NamedTuple

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SPEC = REPO_ROOT / "docs" / "design" / "SCREEN_SPECS.md"

#: Path-looking backticked token, e.g. ``app/lib/router.dart`` or ``index.html``.
PATH_RE = re.compile(r"[A-Za-z0-9_./-]+\.(?:dart|html|yaml|md)$")
#: A backticked token of any kind.
TICK_RE = re.compile(r"`([^`\n]+)`")
#: ``→`` (→) optionally repeated with ``/`` separators after a path.
ARROW_RE = re.compile(
    r"`(?P<path>[A-Za-z0-9_./-]+\.(?:dart|html|yaml|md))`"
    r"\s*→\s*(?P<syms>`[^`\n]+`(?:\s*/\s*`[^`\n]+`)*)"
)
#: Tokens we accept as symbol names: Dart identifiers, optionally dotted,
#: plus the HTML/YAML forms ``#id`` and ``<tag>``.
SYMBOL_RE = re.compile(r"^(?:#|<)?_?[A-Za-z][A-Za-z0-9_]*(?:\.[_A-Za-z][A-Za-z0-9_]*)*>?$")
#: Tokens that merely look like identifiers but name assets, not code.
ASSET_RE = re.compile(r"\.(png|jpg|jpeg|svg|webp|xml|json|arb|ttf|apk)$", re.IGNORECASE)
#: The banned anchor shape: a filename *or a symbol* followed by a line number
#: (``app_mn.arb:82``, ``_guardBack:395-398``). Deliberately not limited to the
#: extensions this script can resolve -- the point is to catch the ones it
#: cannot. The stem must contain a letter, so contrast ratios (``2.28:1``,
#: ``15.4:1``) are not stems, and the number must end the token, so CSS-ish
#: values (``min-height:48dp``) are not line numbers.
LINE_ANCHOR_RE = re.compile(
    r"(?P<stem>[A-Za-z0-9_-]*[A-Za-z][A-Za-z0-9_.-]*):\d+(?:-\d+)?(?![\w.])"
)
#: Stems that are URI schemes, not code: ``tel:102`` is an emergency number.
URI_SCHEME_RE = re.compile(
    r"^(?:tel|sms|mailto|https?|wss?|geo|market|nostr|package)$", re.IGNORECASE
)
#: A single-backtick code span: one that is neither opened nor closed by a
#: second backtick, so a ``…`` span quoting a literal backtick is not one.
SPAN_RE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
#: A double-backtick span, used in this spec to quote code spans verbatim --
#: which is where the before/after examples of the banned shape live.
QUOTED_SPAN_RE = re.compile(r"``.+?``", re.DOTALL)
FILE_BLOCK_PREFIX = "**Файл:**"
#: A ``**Файл:**`` block continues only onto wrapped-path lines; anything that
#: opens a new labelled field, heading, list item or table row ends it.
BLOCK_BREAK_RE = re.compile(r"^\s*(?:\*\*|#|-|\||>|\d+\.)")

#: Declaration keywords used to report how many anchors are declarations.
DECL_RE_TEMPLATE = (
    r"(?:class|enum|mixin|extension|typedef)\s+{name}\b"
    r"|(?:^|\s){name}\s*(?:<[^\n>]*>)?\s*\("
    r"|(?:^|\s){name}\s*="
)


class Anchor(NamedTuple):
    """One (file, symbol) pair as written at `spec_line` of the spec."""

    path: str
    symbol: str
    spec_line: int


def _is_path(token: str) -> bool:
    return bool(PATH_RE.match(token.strip()))


def _is_symbol(token: str) -> bool:
    token = token.strip()
    if _is_path(token) or ASSET_RE.search(token):
        return False
    return bool(SYMBOL_RE.match(token))


def _split_symbols(group: str) -> list[str]:
    return [m.group(1).strip() for m in TICK_RE.finditer(group)]


def _arrow_anchors(line: str, lineno: int) -> Iterator[Anchor]:
    for match in ARROW_RE.finditer(line):
        path = match.group("path")
        for symbol in _split_symbols(match.group("syms")):
            if _is_symbol(symbol):
                yield Anchor(path, symbol, lineno)


def _file_block_anchors(block: list[tuple[int, str]]) -> Iterator[Anchor]:
    """Symbols in a ``**Файл:**`` block, bound to the nearest preceding path."""
    current: str | None = None
    for lineno, line in block:
        for match in TICK_RE.finditer(line):
            token = match.group(1).strip()
            if _is_path(token):
                current = token
            elif current and _is_symbol(token):
                yield Anchor(current, token, lineno)


def collect_anchors(spec: Path) -> list[Anchor]:
    """Parse `spec` and return every (file, symbol, spec line) anchor in it."""
    lines = spec.read_text(encoding="utf-8").split("\n")
    anchors: list[Anchor] = []
    block: list[tuple[int, str]] = []
    for lineno, line in enumerate(lines, start=1):
        if line.startswith(FILE_BLOCK_PREFIX):
            block = [(lineno, line)]
        elif block and line.strip() and not BLOCK_BREAK_RE.match(line):
            block.append((lineno, line))
        elif block:
            anchors.extend(_file_block_anchors(block))
            block = []
        anchors.extend(_arrow_anchors(line, lineno))
    if block:
        anchors.extend(_file_block_anchors(block))

    seen: set[tuple[str, str]] = set()
    unique: list[Anchor] = []
    for anchor in anchors:
        key = (anchor.path, anchor.symbol)
        if key not in seen:
            seen.add(key)
            unique.append(anchor)
    return unique


def _resolve(path: str) -> Path | None:
    """Map a spec-written path onto a real repo file, or None if absent."""
    direct = REPO_ROOT / path
    if direct.is_file():
        return direct
    matches = [p for p in REPO_ROOT.rglob(Path(path).name) if ".git" not in p.parts]
    tail = path.replace("\\", "/")
    exact = [p for p in matches if p.as_posix().endswith(tail)]
    for candidate in (exact or matches):
        return candidate
    return None


def _bare_name(symbol: str) -> str:
    """``_OffersStep.build`` -> ``build``; ``#status`` -> ``status``."""
    cleaned = symbol.strip("<>#")
    return cleaned.rsplit(".", 1)[-1]


def _occurs(text: str, symbol: str) -> bool:
    for part in symbol.strip("<>#").split("."):
        if not re.search(rf"\b{re.escape(part)}\b", text):
            return False
    return True


def _is_declaration(text: str, symbol: str) -> bool:
    name = re.escape(_bare_name(symbol))
    return bool(re.search(DECL_RE_TEMPLATE.format(name=name), text, re.MULTILINE))


def line_number_anchors(text: str) -> list[tuple[int, str]]:
    """Every ``file.ext:NN`` code span in `text` that is not a quoted example."""
    exempt = [m.span() for m in QUOTED_SPAN_RE.finditer(text)]
    found: list[tuple[int, str]] = []
    for match in SPAN_RE.finditer(text):
        hits = [
            m
            for m in LINE_ANCHOR_RE.finditer(match.group(1))
            if not URI_SCHEME_RE.match(m.group("stem"))
        ]
        if not hits:
            continue
        if any(start <= match.start() and match.end() <= end for start, end in exempt):
            continue
        found.append((text.count("\n", 0, match.start()) + 1, match.group(1)))
    return found


def check(spec: Path) -> int:
    """Check every anchor in `spec`; print a report and return an exit code."""
    stale = line_number_anchors(spec.read_text(encoding="utf-8"))
    anchors = collect_anchors(spec)
    cache: dict[str, str | None] = {}
    failures: list[tuple[Anchor, str]] = []
    declarations = 0

    for anchor in anchors:
        if anchor.path not in cache:
            resolved = _resolve(anchor.path)
            cache[anchor.path] = (
                resolved.read_text(encoding="utf-8", errors="replace")
                if resolved
                else None
            )
        text = cache[anchor.path]
        if text is None:
            failures.append((anchor, "файл олдсонгүй"))
        elif not _occurs(text, anchor.symbol):
            failures.append((anchor, "символ файлд байхгүй"))
        elif _is_declaration(text, anchor.symbol):
            declarations += 1

    files = len({a.path for a in anchors})
    for anchor, reason in failures:
        print(
            f"FAIL {spec.name}:{anchor.spec_line}  {anchor.path} → "
            f"{anchor.symbol}  ({reason})"
        )
    for lineno, span in stale:
        print(
            f"FAIL {spec.name}:{lineno}  `{span}`  "
            f"(мөрийн дугаараар зангуудсан — символ болго)"
        )
    if failures or stale:
        print(
            f"\n{len(failures)} / {len(anchors)} анкор олдсонгүй, "
            f"{len(stale)} мөр-дугаар зангуу ({files} файл)."
        )
        return 1
    print(
        f"OK: {len(anchors)} символ-анкор, {files} файл шалгагдав "
        f"({declarations} нь тодорхойлолт, бусад нь хэрэглээ). "
        f"Мөр-дугаар зангуу: 0."
    )
    return 0


def main(argv: list[str]) -> int:
    # The report is Mongolian, and on Windows `sys.stdout` defaults to cp1252,
    # which cannot encode Cyrillic: printing the summary raised
    # `UnicodeEncodeError` and the run exited 1 even when every anchor
    # resolved. Force UTF-8 rather than trusting `PYTHONIOENCODING` to be set.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    spec = Path(argv[1]).resolve() if len(argv) > 1 else DEFAULT_SPEC
    if not spec.is_file():
        print(f"FAIL: баримт олдсонгүй: {spec}")
        return 1
    return check(spec)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
