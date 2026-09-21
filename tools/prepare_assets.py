#!/usr/bin/env python3
"""Build the audio files consumed by PRE2GUS.COM from an original game copy.

Usage: prepare_assets.py GAME_DIRECTORY OUTPUT_DIRECTORY

The input files are the original Prehistorik 2 ``*.TRK`` and ``SAMPLE.SQZ``
files.  No original or converted data is embedded in this program, and no game
executable is modified.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


TRACKS = (
    "BOULA", "BRAVO", "CARTE", "CODE", "FINAL", "GLACE",
    "KOOL", "MINES", "MONSTER", "MYSTERY", "PRES", "PRESENTA",
)
OUTPUT_NAMES = tuple(f"{stem}.MOD" for stem in TRACKS) + ("PRE2SFX.RAW",)


def find_input(game_dir: Path, filename: str) -> Path:
    """Find one required game file without relying on host case semantics."""
    wanted = filename.casefold()
    matches = [path for path in game_dir.iterdir()
               if path.is_file() and path.name.casefold() == wanted]
    if not matches:
        raise FileNotFoundError(f"missing original game file: {filename}")
    if len(matches) != 1:
        raise ValueError(f"ambiguous original game file: {filename}")
    return matches[0]


def unpack_lzss(data: bytes) -> bytes:
    """Decode the bit-oriented LZSS stream used by PRE2 *.TRK files."""
    if data[:2] != b"\xb4\x4c" or len(data) < 19:
        raise ValueError("not a PRE2 LZSS file")
    pos = 17
    bits = data[pos] | (data[pos + 1] << 8)
    pos += 2
    left = 16
    out = bytearray()

    def bit() -> int:
        nonlocal bits, left, pos
        value = bits & 1
        bits >>= 1
        left -= 1
        if left == 0:
            if pos + 1 >= len(data):
                raise ValueError("truncated LZSS bit stream")
            bits = data[pos] | (data[pos + 1] << 8)
            pos += 2
            left = 16
        return value

    while True:
        if bit():
            if pos >= len(data):
                raise ValueError("truncated LZSS literal")
            out.append(data[pos])
            pos += 1
            continue

        long_distance = bit()
        if pos >= len(data):
            raise ValueError("truncated LZSS match")
        lo = data[pos]
        pos += 1
        hi = 0xFF

        if long_distance:
            hi = ((hi << 1) | bit()) & 0xFF
            if not bit():
                subtract = 2
                for _ in range(3):
                    if bit():
                        break
                    hi = ((hi << 1) | bit()) & 0xFF
                    subtract = (subtract * 2) & 0xFF
                hi = (hi - subtract) & 0xFF

            length_seed = 2
            took_short_form = False
            for _ in range(4):
                length_seed = (length_seed + 1) & 0xFF
                if bit():
                    took_short_form = True
                    break
            if took_short_form:
                length = length_seed
            elif bit():
                length_seed = (length_seed + 1) & 0xFF
                if bit():
                    length_seed = (length_seed + 1) & 0xFF
                length = length_seed
            elif bit():
                if pos >= len(data):
                    raise ValueError("truncated LZSS long length")
                length = data[pos] + 0x11
                pos += 1
            else:
                length_seed = 0
                for _ in range(3):
                    length_seed = ((length_seed << 1) | bit()) & 0xFF
                length = length_seed + 9
        else:
            if bit():
                for _ in range(3):
                    hi = ((hi << 1) | bit()) & 0xFF
                hi = (hi - 1) & 0xFF
                length = 2
            else:
                if lo == hi:
                    break
                length = 2

        encoded = (hi << 8) | lo
        distance = encoded - 0x10000 if encoded & 0x8000 else encoded
        source = len(out) + distance
        if source < 0:
            raise ValueError("invalid LZSS back-reference")
        for _ in range(length):
            out.append(out[source])
            source += 1
    return bytes(out)


def unpack_huffman_rle(data: bytes) -> bytes:
    """Decode the Huffman/RLE representation used by SAMPLE.SQZ."""
    if len(data) < 6:
        raise ValueError("truncated Huffman/RLE header")
    output_size = ((data[0] | (data[1] << 8)) << 16) | data[2] | (data[3] << 8)
    tree_size = data[4] | (data[5] << 8)
    tree = data[6:6 + tree_size]
    if len(tree) != tree_size:
        raise ValueError("truncated Huffman tree")
    bit_pos = (6 + tree_size) * 8
    out = bytearray()

    def bit() -> int:
        nonlocal bit_pos
        byte_pos = bit_pos >> 3
        if byte_pos >= len(data):
            raise ValueError("truncated Huffman bit stream")
        value = (data[byte_pos] >> (7 - (bit_pos & 7))) & 1
        bit_pos += 1
        return value

    def symbol() -> int:
        node = 0
        while True:
            if bit():
                node += 2
            if node + 1 >= len(tree):
                raise ValueError("invalid Huffman node")
            node = tree[node] | (tree[node + 1] << 8)
            if node & 0x8000:
                return node & 0x7FFF

    while len(out) < output_size:
        value = symbol()
        if value < 0x100:
            out.append(value)
            continue
        if not out:
            raise ValueError("RLE run before first literal")
        count = value & 0xFF
        if count == 0:
            count = symbol()
        elif count == 1:
            count = ((symbol() & 0xFF) << 8) | (symbol() & 0xFF)
        out.extend(bytes((out[-1],)) * count)
    return bytes(out[:output_size])


def validate_mod(data: bytes, name: str) -> None:
    if len(data) < 1084 or data[1080:1084] != b"M.K.":
        raise ValueError(f"{name}: decoded data is not a four-channel M.K. module")
    song_len = data[950]
    if not 1 <= song_len <= 128:
        raise ValueError(f"{name}: invalid order length {song_len}")
    patterns = max(data[952:952 + song_len]) + 1
    sample_bytes = 0
    for index in range(31):
        off = 20 + index * 30 + 22
        sample_bytes += int.from_bytes(data[off:off + 2], "big") * 2
    expected = 1084 + patterns * 1024 + sample_bytes
    if len(data) != expected:
        raise ValueError(f"{name}: layout ends at {expected}, decoded file has {len(data)} bytes")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def convert_assets(game_dir: Path, output_dir: Path) -> list[Path]:
    """Validate and convert the required original assets into *output_dir*."""
    game_dir = game_dir.resolve()
    output_dir = output_dir.resolve()
    if not game_dir.is_dir():
        raise NotADirectoryError(f"game directory not found: {game_dir}")

    converted: dict[str, bytes] = {}
    for stem in TRACKS:
        source = find_input(game_dir, f"{stem}.TRK")
        decoded = unpack_lzss(source.read_bytes())
        validate_mod(decoded, source.name)
        converted[f"{stem}.MOD"] = decoded

    sample_source = find_input(game_dir, "SAMPLE.SQZ")
    sfx = unpack_huffman_rle(sample_source.read_bytes())
    if len(sfx) != 60_768:
        raise ValueError(
            f"SAMPLE.SQZ: expected 60768 decoded bytes, got {len(sfx)}"
        )
    converted["PRE2SFX.RAW"] = sfx

    # Do not leave a half-installed asset set: decode and validate everything
    # before creating any output file.
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    for filename in OUTPUT_NAMES:
        target = output_dir / filename
        temporary = output_dir / f".{filename}.tmp"
        temporary.write_bytes(converted[filename])
        temporary.replace(target)
        outputs.append(target)
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert original Prehistorik 2 audio for PRE2GUS"
    )
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    outputs = convert_assets(args.game_dir, args.output_dir)
    for path in outputs:
        print(f"{path.name:12} {path.stat().st_size:6} {digest(path)}")


if __name__ == "__main__":
    main()
