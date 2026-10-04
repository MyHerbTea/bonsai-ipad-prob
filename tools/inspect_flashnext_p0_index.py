#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("index_json", type=Path)
    parser.add_argument("--preferred-shard", default="model-00008-of-00008.safetensors")
    args = parser.parse_args()

    data = json.loads(args.index_json.read_text(encoding="utf-8"))
    weight_map = data.get("weight_map", data)
    if not isinstance(weight_map, dict):
        raise SystemExit("index JSON has no usable weight_map")

    candidates = []
    for key, shard in weight_map.items():
        if ".switch_mlp." not in key or not key.endswith(".weight"):
            continue
        base = key[:-len(".weight")]
        scales_key = base + ".scales"
        biases_key = base + ".biases"
        if scales_key not in weight_map or biases_key not in weight_map:
            continue
        same_shard = (
            weight_map[scales_key] == shard
            and weight_map[biases_key] == shard
        )
        candidates.append({
            "weight": key,
            "scales": scales_key,
            "biases": biases_key,
            "shard": shard,
            "same_shard": same_shard,
        })

    same_shard = [c for c in candidates if c["same_shard"]]
    preferred = [c for c in same_shard if c["shard"] == args.preferred_shard]

    print(f"switch_mlp_weight_candidates={len(candidates)}")
    print(f"complete_same_shard_candidates={len(same_shard)}")
    print(f"preferred_shard={args.preferred_shard}")
    print(f"preferred_complete_candidates={len(preferred)}")

    for item in preferred[:12]:
        print("candidate=" + item["weight"])

    if not preferred:
        print("result=FAIL")
        return 2

    print("result=PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
