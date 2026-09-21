#!/usr/bin/env python3
"""Fail if a repository tree contains original or converted game assets."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


FORBIDDEN_SUFFIXES = {
    ".com", ".exe", ".trk", ".sqz", ".mod", ".raw",
    ".zip", ".rar", ".7z", ".lha", ".iso",
}
ALLOWED_BINARIES = {
    Path("dist/INSTALL.COM"),
    Path("dist/PRE2GUS.COM"),
}
REFERENCE_EXE_SHA256 = (
    "e1a7f875b2806551e3f1a8e393b5dfedd5825c402528a24ed90f21e08a2a1142"
)
ARCHIVE_MAGICS = (b"PK\x03\x04", b"Rar!\x1a\x07", b"7z\xbc\xaf\x27\x1c")


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def audit(root: Path) -> list[str]:
    failures: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or ".git" in path.parts:
            continue
        relative = path.relative_to(root)
        if (relative not in ALLOWED_BINARIES
                and path.suffix.casefold() in FORBIDDEN_SUFFIXES):
            failures.append(f"forbidden asset/archive type: {relative}")
            continue
        if digest(path) == REFERENCE_EXE_SHA256:
            failures.append(f"original PRE2.EXE content: {relative}")
        with path.open("rb") as handle:
            magic = handle.read(8)
        if any(magic.startswith(signature) for signature in ARCHIVE_MAGICS):
            failures.append(f"archive content is not allowed: {relative}")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()
    failures = audit(root)
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}")
        raise SystemExit(1)
    print("Repository audit passed: no original or generated game assets found.")


if __name__ == "__main__":
    main()
