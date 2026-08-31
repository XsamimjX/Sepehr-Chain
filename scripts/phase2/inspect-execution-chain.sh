#!/usr/bin/env bash
set -euo pipefail

rpc_port="${1:-18545}"

rpc() {
    local method="$1"
    local params="${2:-[]}" 
    curl --silent --show-error --fail \
        --header 'content-type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
        "http://127.0.0.1:$rpc_port"
}

head_hex="$(rpc eth_blockNumber | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])')"
head_number=$((head_hex))

for ((number = 0; number <= head_number; number++)); do
    rpc eth_getBlockByNumber "[\"$(printf '0x%x' "$number")\",false]" |
        python3 -c 'import json,sys; b=json.load(sys.stdin)["result"]; print(b["number"], b["hash"], b["miner"], b["difficulty"], b.get("totalDifficulty"))'
done
