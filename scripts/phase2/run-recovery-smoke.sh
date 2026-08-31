#!/usr/bin/env bash
set -euo pipefail

repo="/mnt/d/Projects/SEPEHR"
run_root="/home/mmd/sepehr-phase2-recovery-smoke"
nethermind="$repo/sepehr-chain/artifacts/nethermind/bin/linux-x64-patched/nethermind"
chainspec="$repo/sepehr-chain/config/phase2/execution-nethermind.json"
node_config="$repo/sepehr-chain/config/phase2/nethermind-node.json"
jwt="$repo/sepehr-chain/work/jwt.hex"

if [[ "$run_root" != /home/mmd/sepehr-phase2-* ]]; then
    echo "refusing unsafe run directory: $run_root" >&2
    exit 64
fi

pids=()
stop_processes() {
    if ((${#pids[@]})); then
        kill "${pids[@]}" 2>/dev/null || true
        wait "${pids[@]}" 2>/dev/null || true
        pids=()
    fi
}
trap stop_processes EXIT INT TERM

rpc() {
    local port="$1"
    local method="$2"
    local params="${3:-[]}" 
    curl --silent --show-error --fail \
        --header 'content-type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
        "http://127.0.0.1:$port"
}

wait_rpc() {
    local port="$1"
    for _ in $(seq 1 120); do
        if rpc "$port" web3_clientVersion >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "RPC $port did not become ready" >&2
    return 1
}

start_execution() {
    local node="$1"
    local mining="$2"
    local peers="${3:-}"
    local rpc_port=$((18544 + node))
    local engine_port=$((18550 + node))
    local p2p_port=$((30312 + node))
    local p2p_ip="127.0.0.$((10 + node))"
    local mining_key
    mining_key="$(sed -n "${node}p" "$run_root/mining-keys.txt")"
    local args=(
        --config "$node_config"
        --Init.ChainSpecPath "$chainspec"
        --Init.DataDir "$run_root/execution-$node"
        --Init.BaseDbPath "$run_root/execution-$node/db"
        --Init.LogDirectory "$run_root/execution-$node/logs"
        --KeyStore.KeyStoreDirectory "$run_root/execution-$node/keystore"
        --JsonRpc.Port "$rpc_port"
        --JsonRpc.WebSocketsPort "$rpc_port"
        --JsonRpc.EngineHost 127.0.0.1
        --JsonRpc.EnginePort "$engine_port"
        --JsonRpc.JwtSecretFile "$jwt"
        --JsonRpc.EnabledModules Admin,Eth,Net,Web3,Subscribe
        --Network.P2PPort "$p2p_port"
        --Network.DiscoveryPort "$p2p_port"
        --Network.LocalIp "$p2p_ip"
        --Network.ExternalIp "$p2p_ip"
        --Init.DiscoveryEnabled false
        --Network.OnlyStaticPeers true
        --Mining.Enabled "$mining"
        --KeyStore.TestNodeKey "$mining_key"
    )
    if [[ -n "$peers" ]]; then
        args+=(--Network.StaticPeers "$peers")
    fi
    mkdir -p "$run_root/execution-$node"
    "$nethermind" "${args[@]}" >"$run_root/execution-$node/stdout.log" 2>"$run_root/execution-$node/stderr.log" &
    pids+=("$!")
}

rm -rf "$run_root"
mkdir -p "$run_root"
for node in 1 2 3 4; do
    printf 'sepehr-phase2-miner-%s' "$node" | sha256sum | cut -d' ' -f1
done > "$run_root/mining-keys.txt"
chmod 600 "$run_root/mining-keys.txt"

for node in 1 2 3 4; do
    start_execution "$node" false
done
for node in 1 2 3 4; do
    wait_rpc $((18544 + node))
done

enodes=()
for node in 1 2 3 4; do
    enodes+=("$(rpc $((18544 + node)) admin_nodeInfo | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["enode"])')")
done
stop_processes

for node in 1 2 3 4; do
    peers=""
    for peer in 1 2 3 4; do
        if [[ "$peer" -ne "$node" ]]; then
            peers+="${peers:+,}${enodes[$((peer - 1))]}"
        fi
    done
    start_execution "$node" true "$peers"
done
for node in 1 2 3 4; do
    wait_rpc $((18544 + node))
done

for node in 1 2 3 4; do
    rpc $((18544 + node)) net_peerCount
done

echo "execution mesh ready at $run_root"
wait
