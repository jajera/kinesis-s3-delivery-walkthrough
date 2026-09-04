#!/usr/bin/env python3
"""Fix broken GFM markdown tables without rewriting healthy ones.

Handles the common agent failure mode around separator rows and unescaped
pipes inside cells (e.g. `a|b` split into extra columns, or a missing/short
`|---|` row).

Skips fenced code blocks. Path comes from argv[1] or STDIN JSON
(`filePath` / `path` / `file`) for Kiro hooks.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SEP_CELL = re.compile(r"^:?-+:?$")
FENCE = re.compile(r"^(`{3,}|~{3,})")


def dirty_markdown_paths() -> list[Path]:
    """Markdown files with unstaged/untracked changes (Kiro runCommand has no file arg)."""
    import subprocess

    paths: set[Path] = set()
    try:
        tracked = subprocess.run(
            ["git", "ls-files", "-m", "--", "*.md", "*.markdown"],
            check=False,
            capture_output=True,
            text=True,
        )
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard", "--", "*.md", "*.markdown"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return []
    for blob in (tracked.stdout, untracked.stdout):
        for line in blob.splitlines():
            line = line.strip()
            if line:
                paths.add(Path(line))
    return sorted(p for p in paths if p.is_file())


def resolve_paths(argv: list[str], stdin_text: str) -> list[Path]:
    if len(argv) >= 2 and argv[1] in {"--dirty", "--changed"}:
        return dirty_markdown_paths()

    if len(argv) >= 2 and argv[1].strip() and argv[1] not in {"{{filePath}}", "{{file}}"}:
        return [Path(p).expanduser() for p in argv[1:] if p.strip()]

    raw = stdin_text.strip()
    if not raw:
        return dirty_markdown_paths()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        candidate = Path(raw)
        return [candidate] if candidate.exists() else dirty_markdown_paths()

    for key in ("filePath", "path", "file", "filepath"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return [Path(value).expanduser()]
    return dirty_markdown_paths()


def split_row(line: str) -> list[str] | None:
    """Split a table row on unescaped pipes only."""
    stripped = line.rstrip("\n")
    if "|" not in stripped:
        return None
    # Keep leading indentation out of cell content, but require pipe structure.
    working = stripped.strip()
    if not (working.startswith("|") or working.endswith("|")):
        return None

    cells: list[str] = []
    buf: list[str] = []
    i = 0
    # Drop a single leading pipe
    if working.startswith("|"):
        working = working[1:]
    # Drop a single trailing pipe (unescaped)
    if working.endswith("|") and not working.endswith("\\|"):
        working = working[:-1]

    while i < len(working):
        ch = working[i]
        if ch == "\\" and i + 1 < len(working) and working[i + 1] == "|":
            buf.append("|")
            i += 2
            continue
        if ch == "|":
            cells.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    cells.append("".join(buf).strip())
    return cells


def is_separator_row(cells: list[str]) -> bool:
    return bool(cells) and all(SEP_CELL.match(cell.replace(" ", "")) for cell in cells)


def escape_cell(text: str) -> str:
    return text.replace("|", "\\|")


def format_row(cells: list[str], width: int) -> str:
    padded = list(cells[:width]) + [""] * max(0, width - len(cells))
    return "| " + " | ".join(escape_cell(c) for c in padded) + " |"


def separator_row(width: int, sample: list[str] | None = None) -> str:
    parts: list[str] = []
    for i in range(width):
        style = "---"
        if sample and i < len(sample):
            token = sample[i].replace(" ", "")
            left = token.startswith(":")
            right = token.endswith(":")
            if left and right:
                style = ":---:"
            elif left:
                style = ":---"
            elif right:
                style = "---:"
        parts.append(style)
    return "| " + " | ".join(parts) + " |"


def in_fence(line: str, fence_marker: str | None) -> tuple[bool, str | None]:
    match = FENCE.match(line.strip())
    if not match:
        return fence_marker is not None, fence_marker
    marker = match.group(1)[0] * len(match.group(1))
    if fence_marker is None:
        return True, marker
    if line.strip().startswith(fence_marker):
        return False, None
    return True, fence_marker


def drop_trailing_empty(cells: list[str]) -> list[str]:
    trimmed = list(cells)
    while trimmed and trimmed[-1] == "":
        trimmed.pop()
    return trimmed or [""]


def coerce_row(cells: list[str], width: int) -> list[str]:
    if len(cells) == width:
        return cells
    if len(cells) < width:
        return cells + [""] * (width - len(cells))
    # One extra cell usually means an unescaped "|" inside a non-final column
    # (e.g. Type = `system-managed | customer-managed`). Keep the last column.
    if len(cells) == width + 1 and width >= 2:
        merged = f"{cells[width - 2]} | {cells[width - 1]}"
        return cells[: width - 2] + [merged, cells[width]]
    head = cells[: width - 1]
    tail = " | ".join(cells[width - 1 :])
    return head + [tail]


def table_is_healthy(
    header: list[str], sep: list[str], body: list[list[str]]
) -> bool:
    width = len(header)
    if width == 0 or (header and header[-1] == ""):
        return False
    if len(sep) != width:
        return False
    return all(len(row) == width for row in body)


def format_tables(text: str) -> tuple[str, int]:
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    fixes = 0
    fence_marker: str | None = None

    while i < len(lines):
        line = lines[i]
        fenced, fence_marker = in_fence(line, fence_marker)
        if fenced:
            out.append(line)
            i += 1
            continue

        header = split_row(line)
        if header is None or i + 1 >= len(lines):
            out.append(line)
            i += 1
            continue

        sep_line = lines[i + 1]
        next_fenced, _ = in_fence(sep_line, fence_marker)
        if next_fenced:
            out.append(line)
            i += 1
            continue

        sep_cells = split_row(sep_line)
        if sep_cells is None or not is_separator_row(sep_cells):
            out.append(line)
            i += 1
            continue

        body_rows: list[list[str]] = []
        j = i + 2
        while j < len(lines):
            body_line = lines[j]
            body_fenced, _ = in_fence(body_line, fence_marker)
            if body_fenced or not body_line.strip():
                break
            cells = split_row(body_line)
            if cells is None:
                break
            body_rows.append(cells)
            j += 1

        if table_is_healthy(header, sep_cells, body_rows):
            # Still normalize separator row spacing for MD060 compliance
            width = len(header)
            expected_sep = separator_row(width, sep_cells)
            if lines[i + 1] != expected_sep:
                out.append(lines[i])  # header
                out.append(expected_sep)  # normalized separator
                out.extend(lines[i + 2:j])  # body rows
                fixes += 1
            else:
                out.extend(lines[i:j])
            i = j
            continue

        header = drop_trailing_empty(header)
        width = max(len(header), 1)
        rebuilt = [
            format_row(header, width),
            separator_row(width, sep_cells),
            *[
                format_row(coerce_row(drop_trailing_empty(row), width), width)
                for row in body_rows
            ],
        ]
        if rebuilt != lines[i:j]:
            fixes += 1
        out.extend(rebuilt)
        i = j

    result = "\n".join(out)
    if text.endswith("\n"):
        result += "\n"
    return result, fixes


def process_file(path: Path) -> int:
    if path.suffix.lower() not in {".md", ".markdown"}:
        print(f"format-md-tables: skip non-markdown {path}")
        return 0
    if not path.is_file():
        print(f"format-md-tables: missing file {path}", file=sys.stderr)
        return 2

    original = path.read_text(encoding="utf-8")
    updated, fixes = format_tables(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"format-md-tables: fixed {fixes} table(s) in {path}")
    else:
        print(f"format-md-tables: ok {path}")
    return 0


def main() -> int:
    stdin_text = ""
    if not sys.stdin.isatty():
        stdin_text = sys.stdin.read()
    paths = resolve_paths(sys.argv, stdin_text)
    if not paths:
        print("format-md-tables: skip (no markdown paths)")
        return 0
    rc = 0
    for path in paths:
        rc = max(rc, process_file(path))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
