#!/usr/bin/env python3

import argparse
import hashlib
import json
import pathlib
import re

ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")
ENODE = re.compile(r"^enode://[0-9a-fA-F]{128}@[A-Za-z0-9.:-]+$", re.ASCII)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the immutable Sepehr Testnet execution genesis")
    parser.add_argument("--faucet-address", action="append", default=[])
    parser.add_argument("--execution-bootnode", action="append", default=[])
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if len(args.faucet_address) != 4:
        parser.error("exactly four --faucet-address values are required")
    if any(not ADDRESS.fullmatch(address) for address in args.faucet_address):
        parser.error("every --faucet-address must be a 20-byte 0x address")
    faucets = [address.lower() for address in args.faucet_address]
    if len(set(faucets)) != 4:
        parser.error("faucet addresses must be distinct")
    if len(args.execution_bootnode) < 2:
        parser.error("at least two --execution-bootnode values are required")
    if any(not ENODE.fullmatch(node) for node in args.execution_bootnode):
        parser.error("every execution bootnode must be a complete enode URL")

    root = pathlib.Path(__file__).resolve().parents[2]
    template_path = root / "config" / "testnet" / "execution-nethermind.template.json"
    output_path = pathlib.Path(args.output).resolve()
    document = json.loads(template_path.read_text(encoding="utf-8"))
    allocation = document["accounts"].pop("__FAUCET_ADDRESS__")
    for faucet in faucets:
        document["accounts"][faucet] = allocation.copy()
    document["nodes"] = args.execution_bootnode

    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(document, indent=2, sort_keys=False) + "\n"
    output_path.write_text(payload, encoding="utf-8")
    digest = hashlib.sha256(payload.encode()).hexdigest()
    print(json.dumps({"output": str(output_path), "sha256": digest, "faucetAddresses": faucets}))


if __name__ == "__main__":
    main()
