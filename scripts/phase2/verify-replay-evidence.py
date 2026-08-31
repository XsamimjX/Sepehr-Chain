#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify-replay-evidence.py RUN_ROOT")

    run_root = Path(sys.argv[1])
    before = load(run_root / "evidence-pre-outage.json")
    after = load(run_root / "evidence-post-outage.json")
    replayed_blocks = after["blocks"][: len(before["blocks"])]

    if replayed_blocks != before["blocks"]:
        raise SystemExit("stored PoW/PoS history changed after full client restart")

    before_canary = before["canary"]
    after_canary = after["canary"]
    stable_canary_fields = (
        "address",
        "transactionHash",
        "code",
        "storage0",
        "balance",
        "deployerNonce",
        "receipt",
        "deploymentBlock",
    )
    for field in stable_canary_fields:
        if before_canary[field] != after_canary[field]:
            raise SystemExit(f"canary field changed after replay: {field}")

    difficulties = [int(block["difficulty"], 16) for block in before["blocks"]]
    if not any(difficulty > 0 for difficulty in difficulties):
        raise SystemExit("replay evidence contains no PoW blocks")
    if not any(difficulty == 0 for difficulty in difficulties[1:]):
        raise SystemExit("replay evidence contains no PoS blocks")

    print(
        f"replay verified: {len(replayed_blocks)} blocks across PoW and PoS; "
        "canary state and receipt unchanged"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
