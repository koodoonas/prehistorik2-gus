#!/usr/bin/env python3
"""Install PRE2GUS into a user's existing Prehistorik 2 directory.

Only locally supplied game assets are decoded.  This repository contains no
Prehistorik 2 executable, music module, compressed track, or sound-effect data.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from tools.prepare_assets import OUTPUT_NAMES, convert_assets, find_input


ROOT = Path(__file__).resolve().parent
VERIFIED_EXE_SHA256 = (
    "e1a7f875b2806551e3f1a8e393b5dfedd5825c402528a24ed90f21e08a2a1142"
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_checked(source: Path, destination: Path, force: bool) -> None:
    if destination.exists() and sha256(source) != sha256(destination) and not force:
        raise FileExistsError(
            f"refusing to replace different file: {destination.name}; "
            "rerun with --force if intentional"
        )
    shutil.copy2(source, destination)


def assemble(source: Path, output: Path) -> None:
    nasm = shutil.which("nasm")
    if not nasm:
        raise RuntimeError("NASM was not found in PATH; omit --build to use dist/")
    subprocess.run(
        [nasm, "-Wall", "-f", "bin", "-o", str(output), str(source)],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install PRE2GUS and derive its audio from an original game copy"
    )
    parser.add_argument("game_dir", type=Path,
                        help="directory containing PRE2.EXE, *.TRK and SAMPLE.SQZ")
    parser.add_argument("--build", action="store_true",
                        help="rebuild both DOS programs instead of using dist/")
    parser.add_argument("--force", action="store_true",
                        help="replace different PRE2GUS-generated files")
    args = parser.parse_args()

    game_dir = args.game_dir.resolve()
    if not game_dir.is_dir():
        parser.error(f"game directory not found: {game_dir}")

    game_exe = find_input(game_dir, "PRE2.EXE")
    exe_hash = sha256(game_exe)
    if exe_hash == VERIFIED_EXE_SHA256:
        print("PRE2.EXE: verified reference build")
    else:
        print("WARNING: PRE2.EXE is not the fully verified reference build.")
        print(f"         SHA-256 {exe_hash}")
        print("         The launcher will patch only if its in-memory signatures match.")

    with tempfile.TemporaryDirectory(prefix="pre2gus-") as temporary_name:
        temporary = Path(temporary_name)
        converted = convert_assets(game_dir, temporary)
        launcher = temporary / "PRE2GUS.COM"
        dos_installer = temporary / "INSTALL.COM"
        if args.build:
            assemble(ROOT / "src" / "pre2gus.asm", launcher)
            assemble(ROOT / "tools" / "install_dos.asm", dos_installer)
        else:
            shutil.copy2(ROOT / "dist" / "PRE2GUS.COM", launcher)
            shutil.copy2(ROOT / "dist" / "INSTALL.COM", dos_installer)

        install_files = converted + [
            launcher,
            dos_installer,
            ROOT / "dos" / "RUN_GUS.BAT",
            ROOT / "dos" / "TEST_GUS.BAT",
        ]
        for source in install_files:
            copy_checked(source, game_dir / source.name, args.force)

    print(f"Installed PRE2GUS in {game_dir}")
    print("Generated locally: " + ", ".join(OUTPUT_NAMES))
    print("Run TEST_GUS.BAT first, then RUN_GUS.BAT.")


if __name__ == "__main__":
    main()
