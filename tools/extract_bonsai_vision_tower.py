#!/usr/bin/env python3
"""
Extract only the Qwen/Bonsai vision tower from Prism's monolithic MLX safetensors
using HTTP Range requests. No third-party Python packages are required.

Default source:
https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-mlx-2bit/resolve/main/model.safetensors

The output contains module-local keys (patch_embed.*, blocks.*, merger.*, pos_embed.*)
so RC1.22 can load it directly into the isolated MLX Vision Tower.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import urllib.request

DEFAULT_URL = (
    "https://huggingface.co/prism-ml/"
    "Ternary-Bonsai-2-27B-mlx-2bit/resolve/main/model.safetensors"
)

PREFIXES = (
    "vision_tower.",
    "model.visual.",
    "model.vision_tower.",
)

def request_range(url: str, start: int, end: int):
    req = urllib.request.Request(
        url,
        headers={
            "Range": f"bytes={start}-{end}",
            "User-Agent": "Bonsai-RC1.22-VisionExtractor/1.0",
        },
    )
    resp = urllib.request.urlopen(req, timeout=60)
    status = getattr(resp, "status", None)
    content_range = resp.headers.get("Content-Range")
    if status != 206 and not content_range:
        resp.close()
        raise RuntimeError(
            "Server did not honor HTTP Range. "
            "Refusing to download the full 8.6GB model."
        )
    return resp

def read_exact_range(url: str, start: int, end: int) -> bytes:
    with request_range(url, start, end) as resp:
        data = resp.read()
    expected = end - start + 1
    if len(data) != expected:
        raise RuntimeError(
            f"Range length mismatch: expected {expected}, got {len(data)}"
        )
    return data

def strip_prefix(name: str) -> str | None:
    for prefix in PREFIXES:
        if name.startswith(prefix):
            return name[len(prefix):]
    return None

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument(
        "--output",
        default="Bonsai-2-27B-vision_tower-fp16.safetensors",
    )
    args = parser.parse_args()

    print("Reading safetensors header...")
    head8 = read_exact_range(args.url, 0, 7)
    header_len = struct.unpack("<Q", head8)[0]
    if header_len <= 0 or header_len > 128 * 1024 * 1024:
        raise RuntimeError(f"Suspicious header length: {header_len}")

    header_bytes = read_exact_range(
        args.url,
        8,
        8 + header_len - 1,
    )
    header = json.loads(header_bytes.decode("utf-8").rstrip(" "))

    selected = []
    for raw_name, spec in header.items():
        if raw_name == "__metadata__":
            continue
        local_name = strip_prefix(raw_name)
        if local_name is None:
            continue
        start, end = spec["data_offsets"]
        selected.append((start, end, raw_name, local_name, spec))

    if not selected:
        raise RuntimeError(
            "No vision_tower/model.visual tensors found in source header."
        )

    selected.sort(key=lambda row: row[0])
    cursor = 0
    out_header = {}
    total = 0
    for start, end, raw_name, local_name, spec in selected:
        size = end - start
        out_header[local_name] = {
            "dtype": spec["dtype"],
            "shape": spec["shape"],
            "data_offsets": [cursor, cursor + size],
        }
        cursor += size
        total += size

    metadata = header.get("__metadata__", {})
    out_header["__metadata__"] = {
        **metadata,
        "bonsai_component": "vision_tower",
        "bonsai_source": args.url,
        "bonsai_extractor": "RC1.22.0",
    }

    encoded = json.dumps(
        out_header,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    padding = (-len(encoded)) % 8
    encoded += b" " * padding

    data_base = 8 + header_len
    out_path = os.path.abspath(args.output)
    tmp_path = out_path + ".part"

    print(f"Vision tensors: {len(selected)}")
    print(f"Payload: {total / (1024**3):.3f} GiB")
    print(f"Output: {out_path}")

    done = 0
    try:
        with open(tmp_path, "wb") as out:
            out.write(struct.pack("<Q", len(encoded)))
            out.write(encoded)

            # Vision tensors are normally clustered. Merge exactly-contiguous
            # ranges to avoid hundreds of HTTP requests without downloading
            # any language-model bytes.
            groups = []
            for row in selected:
                start, end = row[0], row[1]
                if groups and groups[-1][1] == start:
                    groups[-1] = (groups[-1][0], end)
                else:
                    groups.append((start, end))

            for gi, (start, end) in enumerate(groups, 1):
                absolute_start = data_base + start
                absolute_end = data_base + end - 1
                with request_range(args.url, absolute_start, absolute_end) as resp:
                    remaining = end - start
                    while remaining:
                        chunk = resp.read(min(8 * 1024 * 1024, remaining))
                        if not chunk:
                            raise RuntimeError("Unexpected EOF during range download")
                        out.write(chunk)
                        remaining -= len(chunk)
                        done += len(chunk)
                        pct = done * 100.0 / total
                        print(
                            f"\rDownloading vision payload: {pct:6.2f}% "
                            f"({done / (1024**2):.0f}/{total / (1024**2):.0f} MiB)",
                            end="",
                            flush=True,
                        )
                if gi == len(groups):
                    print()

        os.replace(tmp_path, out_path)
    except Exception:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise

    print("DONE")
    print(f"Created: {out_path}")
    print(
        "Copy this .safetensors file to the iPad, select it in "
        "RC1.22.0 Advanced → MLX Vision Sidecar Probe."
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
