#!/usr/bin/env python3

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config" / "testnet"

manifest = json.loads((CONFIG / "network-manifest.json").read_text(encoding="utf-8"))
template = json.loads((CONFIG / "execution-nethermind.template.json").read_text(encoding="utf-8"))
node = json.loads((CONFIG / "node-public-low-resource.json").read_text(encoding="utf-8"))
consensus = (CONFIG / "consensus.yaml").read_text(encoding="utf-8")

assert manifest["chainId"] == 7331
assert manifest["monetaryValue"] is False and manifest["redeemable"] is False
assert template["params"]["networkId"] == "0x1ca3"
assert template["params"]["terminalTotalDifficulty"] == "0x8400"
assert template["accounts"]["__FAUCET_ADDRESS__"]["balance"] == "0x33b2e3c9fd0803ce8000000"
assert node["Init"]["DiscoveryEnabled"] is True
assert node["Network"]["OnlyStaticPeers"] is False
assert node["Discovery"]["UseDefaultDiscv5Bootnodes"] is False
assert node["JsonRpc"]["EngineHost"] == "127.0.0.1"
assert node["Pruning"]["Mode"] == "Memory"
assert "PRESET_BASE: mainnet" in consensus
assert "DEPOSIT_CHAIN_ID: 7331" in consensus
assert "TERMINAL_TOTAL_DIFFICULTY: 33792" in consensus

print("Sepehr Testnet configuration verified.")
