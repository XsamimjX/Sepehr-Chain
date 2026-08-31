#!/usr/bin/env bash
set -euo pipefail

repo="/mnt/d/Projects/SEPEHR"
run_id="${1:-clean-1}"
run_root="/home/mmd/sepehr-phase2-$run_id"
wallet_root="${SEPEHR_VALIDATOR_WALLET_ROOT:-/home/mmd/sepehr-phase2-recovery-wallets}"
nethermind="$repo/sepehr-chain/artifacts/nethermind/bin/linux-x64-patched/nethermind"
beacon="$repo/sepehr-chain/artifacts/prysm/beacon-chain-linux-amd64-equal-head-lf"
validator="$repo/sepehr-chain/artifacts/prysm/validator-linux-amd64-boundary-fix"
prysmctl="$repo/sepehr-chain/artifacts/prysm/prysmctl-linux-amd64"
go_binary="${SEPEHR_GO_BINARY:-/snap/bin/go}"
prysm_source="$repo/sepehr-chain/upstream/prysm-lf"
canary_source="$repo/sepehr-chain/scripts/phase2/deploy-canary.go"
chainspec="$repo/sepehr-chain/config/phase2/execution-nethermind.json"
node_config="$repo/sepehr-chain/config/phase2/nethermind-node.json"
consensus_config="$repo/sepehr-chain/config/phase2/consensus.yaml"
jwt="$repo/sepehr-chain/work/jwt.hex"
terminal_total_difficulty="$(awk '/^TERMINAL_TOTAL_DIFFICULTY:/ {print $2}' "$consensus_config")"
mining_handoff_difficulty="$((terminal_total_difficulty - 8192))"

python3 - "$node_config" "$consensus_config" <<'PY'
import json
import pathlib
import sys

node_config = json.loads(pathlib.Path(sys.argv[1]).read_text())
seconds_per_slot = node_config["Blocks"]["SecondsPerSlot"]
consensus_lines = pathlib.Path(sys.argv[2]).read_text().splitlines()
consensus_seconds_per_slot = int(next(line.split(":", 1)[1] for line in consensus_lines if line.startswith("SECONDS_PER_SLOT:")))
slot_duration_ms = int(next(line.split(":", 1)[1] for line in consensus_lines if line.startswith("SLOT_DURATION_MS:")))
if seconds_per_slot != consensus_seconds_per_slot or seconds_per_slot * 1000 != slot_duration_ms:
    raise SystemExit(
        f"EL/CL slot duration mismatch: EL={seconds_per_slot}s, "
        f"CL={consensus_seconds_per_slot}s/{slot_duration_ms}ms"
    )
PY

if [[ ! "$run_id" =~ ^[a-z0-9-]+$ ]] || [[ "$run_root" != /home/mmd/sepehr-phase2-* ]]; then
    echo "invalid run identifier: $run_id" >&2
    exit 64
fi

execution_pids=()
beacon_pids=()
validator_pids=()
recovery_mode=false
centralize_initial_validators=false
network_mode=full
partition_test="${SEPEHR_PHASE2_PARTITION_TEST:-false}"

stop_group() {
    local array_name="$1"
    local -n group="$array_name"
    if ((${#group[@]})); then
        kill "${group[@]}" 2>/dev/null || true
        wait "${group[@]}" 2>/dev/null || true
        group=()
    fi
}

stop_all() {
    stop_group validator_pids
    stop_group beacon_pids
    stop_group execution_pids
}
trap stop_all EXIT INT TERM

rpc() {
    local port="$1"
    local method="$2"
    local params="${3:-[]}" 
    curl --silent --show-error --fail \
        --header 'content-type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
        "http://127.0.0.1:$port"
}

json_result() {
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])'
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

wait_http() {
    local url="$1"
    for _ in $(seq 1 120); do
        if curl --silent --fail "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "HTTP endpoint did not become ready: $url" >&2
    return 1
}

wait_port() {
    local port="$1"
    for _ in $(seq 1 120); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            exec 3>&-
            return 0
        fi
        sleep 1
    done
    echo "TCP port did not become ready: $port" >&2
    return 1
}

wait_peer_id() {
    local log_file="$1"
    for _ in $(seq 1 120); do
        peer_id="$(sed -n 's/.*peer id of \([^ ]*\).*/\1/p' "$log_file" | tail -n 1)"
        if [[ -n "$peer_id" ]]; then
            printf '%s\n' "$peer_id"
            return 0
        fi
        sleep 1
    done
    echo "peer id was not written to $log_file" >&2
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
    execution_pids+=("$!")
}

start_beacon() {
    local node="$1"
    shift
    local peer_addresses=("$@")
    local args=(
        --accept-terms-of-use
        --chain-config-file "$consensus_config"
        --datadir "$run_root/beacon-$node"
        --genesis-state "$run_root/consensus-genesis/genesis.ssz"
        --execution-endpoint "http://127.0.0.1:$((18550 + node))"
        --jwt-secret "$jwt"
        --rpc-port "$((14000 + node))"
        --http-port "$((13500 + node))"
        --p2p-local-ip 127.0.0.1
        --p2p-host-ip 127.0.0.1
        --p2p-tcp-port "$((13000 + node))"
        --p2p-udp-port "$((12000 + node))"
        --p2p-quic-port "$((11000 + node))"
        --disable-quic
        --no-discovery
        --minimum-peers-per-subnet 0
        --p2p-colocation-whitelist 127.0.0.1/32
        --disable-monitoring
        --disable-staking-contract-check
        --disable-log-colors
    )
    if [[ "$recovery_mode" == true ]] || ((${#peer_addresses[@]} == 0)); then
        args+=(--min-sync-peers 0)
    else
        args+=(--min-sync-peers 1)
    fi
    for peer_address in "${peer_addresses[@]}"; do
        args+=(--peer "$peer_address")
    done
    if [[ "$recovery_mode" == true ]]; then
        args+=(--sync-from head)
    fi
    mkdir -p "$run_root/beacon-$node"
    "$beacon" "${args[@]}" >"$run_root/beacon-$node/stdout.log" 2>"$run_root/beacon-$node/stderr.log" &
    beacon_pids+=("$!")
}

start_validator() {
    local node="$1"
    local beacon_node="$node"
    if [[ "$centralize_initial_validators" == true ]]; then
        beacon_node=1
    fi
    mkdir -p "$run_root/validator-$node"
    "$validator" \
        --accept-terms-of-use \
        --chain-config-file "$consensus_config" \
        --datadir "$run_root/validator-$node" \
        --wallet-dir "$wallet_root/wallet-node-$node" \
        --wallet-password-file "$wallet_root/wallet-password.txt" \
        --beacon-rpc-provider "127.0.0.1:$((14000 + beacon_node))" \
        --beacon-rest-api-provider "http://127.0.0.1:$((13500 + beacon_node))" \
        --suggested-fee-recipient 0xb8112E11B9052CFdE93a99960Bc8fe33B3225287 \
        --disable-monitoring \
        --disable-log-colors \
        --graffiti "Sepehr-P2-node-$node" \
        >"$run_root/validator-$node/stdout.log" 2>"$run_root/validator-$node/stderr.log" &
    validator_pids+=("$!")
}

start_consensus_mesh() {
    local peer_ids=()
    local node

    # First open each persistent datadir without peers so Prysm writes its stable
    # libp2p identity. Restart below with every other identity as a static peer.
    for node in 1 2 3 4; do
        start_beacon "$node"
    done
    for node in 1 2 3 4; do
        peer_ids+=("$(wait_peer_id "$run_root/beacon-$node/stderr.log")")
        wait_port $((13500 + node))
    done
    stop_group beacon_pids

    for node in 1 2 3 4; do
        local peer_addresses=()
        local peer_node
        for peer_node in 1 2 3 4; do
            if [[ "$peer_node" -ne "$node" ]]; then
                if [[ "$network_mode" == partition ]] \
                    && ((node <= 2 && peer_node > 2 || node > 2 && peer_node <= 2)); then
                    continue
                fi
                peer_addresses+=("/ip4/127.0.0.1/tcp/$((13000 + peer_node))/p2p/${peer_ids[$((peer_node - 1))]}")
            fi
        done
        start_beacon "$node" "${peer_addresses[@]}"
    done
    for node in 1 2 3 4; do
        wait_port $((13500 + node))
        start_validator "$node"
    done
}

finalized_epoch() {
    curl --silent --fail http://127.0.0.1:13501/eth/v1/beacon/states/head/finality_checkpoints |
        python3 -c 'import json,sys; print(int(json.load(sys.stdin)["data"]["finalized"]["epoch"]))'
}

finalized_checkpoint_for() {
    local node="$1"
    curl --silent --fail "http://127.0.0.1:$((13500 + node))/eth/v1/beacon/states/head/finality_checkpoints" |
        python3 -c 'import json,sys; f=json.load(sys.stdin)["data"]["finalized"]; print(f["epoch"] + ":" + f["root"])'
}

head_slot() {
    curl --silent --fail http://127.0.0.1:13501/eth/v1/beacon/headers/head |
        python3 -c 'import json,sys; print(int(json.load(sys.stdin)["data"]["header"]["message"]["slot"]))'
}

head_slot_for() {
    local node="$1"
    curl --silent --fail "http://127.0.0.1:$((13500 + node))/eth/v1/beacon/headers/head" |
        python3 -c 'import json,sys; print(int(json.load(sys.stdin)["data"]["header"]["message"]["slot"]))'
}

wait_for_head_slot_after() {
    local node="$1"
    local minimum_slot="$2"
    for _ in $(seq 1 240); do
        slot="$(head_slot_for "$node" 2>/dev/null || printf '0')"
        if ((slot > minimum_slot)); then
            return 0
        fi
        sleep 5
    done
    echo "beacon node $node did not advance beyond slot $minimum_slot" >&2
    return 1
}

wait_for_finalized_convergence_after() {
    local minimum_epoch="$1"
    for _ in $(seq 1 240); do
        checkpoints=()
        converged=true
        for node in 1 2 3 4; do
            checkpoint="$(finalized_checkpoint_for "$node" 2>/dev/null || true)"
            checkpoints+=("$checkpoint")
            epoch="${checkpoint%%:*}"
            if [[ -z "$epoch" ]] || ((epoch <= minimum_epoch)); then
                converged=false
            fi
        done
        if [[ "$converged" == true ]] \
            && [[ "${checkpoints[0]}" == "${checkpoints[1]}" ]] \
            && [[ "${checkpoints[0]}" == "${checkpoints[2]}" ]] \
            && [[ "${checkpoints[0]}" == "${checkpoints[3]}" ]]; then
            return 0
        fi
        sleep 5
    done
    echo "all beacon nodes did not converge on a newer finalized checkpoint" >&2
    return 1
}

wait_for_pos() {
    for _ in $(seq 1 180); do
        latest="$(rpc 18545 eth_getBlockByNumber '["latest",false]')"
        if python3 -c 'import json,sys; b=json.load(sys.stdin)["result"]; raise SystemExit(0 if int(b["number"],16)>0 and int(b["difficulty"],16)==0 else 1)' <<<"$latest"; then
            return 0
        fi
        sleep 5
    done
    echo "first canonical PoS block was not observed" >&2
    return 1
}

wait_for_mining_handoff() {
    for _ in $(seq 1 240); do
        latest="$(rpc 18545 eth_getBlockByNumber '["latest",false]')"
        if python3 -c 'import json,sys; b=json.load(sys.stdin)["result"]; raise SystemExit(0 if int(b["totalDifficulty"],16)>=int(sys.argv[1]) else 1)' "$mining_handoff_difficulty" <<<"$latest"; then
            return 0
        fi
        sleep 2
    done
    echo "four-miner handoff height was not observed" >&2
    return 1
}

wait_for_pow_terminal() {
    for _ in $(seq 1 240); do
        latest="$(rpc 18545 eth_getBlockByNumber '["latest",false]')"
        if python3 -c 'import json,sys; b=json.load(sys.stdin)["result"]; raise SystemExit(0 if int(b["totalDifficulty"],16)>=int(sys.argv[1]) and int(b["difficulty"],16)>0 else 1)' "$terminal_total_difficulty" <<<"$latest"; then
            return 0
        fi
        sleep 2
    done
    echo "terminal PoW block was not observed before consensus genesis" >&2
    return 1
}

wait_for_next_converged_pow_block() {
    local previous_height="$1"
    for _ in $(seq 1 180); do
        hashes=()
        heights=()
        converged=true
        for node in 1 2 3 4; do
            block="$(rpc $((18544 + node)) eth_getBlockByNumber '["latest",false]')"
            hashes+=("$(python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["hash"])' <<<"$block")")
            heights+=("$(python3 -c 'import json,sys; print(int(json.load(sys.stdin)["result"]["number"],16))' <<<"$block")")
        done
        if ((heights[0] > previous_height)) \
            && [[ "${heights[0]}" == "${heights[1]}" ]] \
            && [[ "${heights[0]}" == "${heights[2]}" ]] \
            && [[ "${heights[0]}" == "${heights[3]}" ]] \
            && [[ "${hashes[0]}" == "${hashes[1]}" ]] \
            && [[ "${hashes[0]}" == "${hashes[2]}" ]] \
            && [[ "${hashes[0]}" == "${hashes[3]}" ]]; then
            return 0
        fi
        sleep 2
    done
    echo "execution nodes did not converge on the staged PoW block" >&2
    return 1
}

wait_for_execution_convergence() {
    for _ in $(seq 1 120); do
        hashes=()
        converged=true
        for node in 1 2 3 4; do
            block="$(rpc $((18544 + node)) eth_getBlockByNumber '["latest",false]')"
            block_hash="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["hash"])' <<<"$block")"
            total_difficulty="$(python3 -c 'import json,sys; print(int(json.load(sys.stdin)["result"]["totalDifficulty"],16))' <<<"$block")"
            hashes+=("$block_hash")
            if [[ "$total_difficulty" -lt "$terminal_total_difficulty" ]]; then
                converged=false
            fi
        done
        if [[ "$converged" == true ]] && [[ "${hashes[0]}" == "${hashes[1]}" ]] && [[ "${hashes[0]}" == "${hashes[2]}" ]] && [[ "${hashes[0]}" == "${hashes[3]}" ]]; then
            return 0
        fi
        sleep 2
    done
    echo "execution nodes did not converge on one terminal block" >&2
    return 1
}

verify_four_pow_miners() {
    python3 <<'PY'
import json, urllib.request

def rpc(method, params):
    payload = json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params}).encode()
    request = urllib.request.Request("http://127.0.0.1:18545", data=payload, headers={"content-type":"application/json"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)["result"]

head = int(rpc("eth_blockNumber", []), 16)
miners = set()
for number in range(1, head + 1):
    block = rpc("eth_getBlockByNumber", [hex(number), False])
    if int(block["difficulty"], 16) == 0:
        break
    miners.add(block["miner"].lower())
if len(miners) != 4:
    raise SystemExit(f"expected four canonical PoW miners, observed {len(miners)}: {sorted(miners)}")
print("canonical PoW miners:", ",".join(sorted(miners)))
PY
}

wait_for_finality_after() {
    local minimum_epoch="$1"
    for _ in $(seq 1 180); do
        epoch="$(finalized_epoch 2>/dev/null || printf '0')"
        if ((epoch > minimum_epoch)); then
            return 0
        fi
        sleep 5
    done
    echo "finality did not advance beyond epoch $minimum_epoch" >&2
    return 1
}

write_evidence() {
    local stage="$1"
    python3 - "$stage" "$run_root" <<'PY'
import json, pathlib, sys, urllib.request

stage, run_root = sys.argv[1:]

def request(url, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {} if payload is None else {"content-type": "application/json"}
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers)) as response:
        return json.load(response)

head = int(request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]})["result"], 16)
blocks = []
for number in range(head + 1):
    block = request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":[hex(number), False]})["result"]
    blocks.append({key: block.get(key) for key in ("number", "hash", "parentHash", "miner", "difficulty", "totalDifficulty", "nonce", "mixHash", "stateRoot")})
finality = request("http://127.0.0.1:13501/eth/v1/beacon/states/head/finality_checkpoints")["data"]
beacon_head = request("http://127.0.0.1:13501/eth/v1/beacon/headers/head")["data"]
evidence = {"stage": stage, "blocks": blocks, "finality": finality, "beacon_head": beacon_head}
canary_meta = json.loads(pathlib.Path(run_root, "canary-deployment.json").read_text())
address = canary_meta["address"]
transaction_hash = canary_meta["transactionHash"]
deployer = canary_meta["deployer"]
canary = {
    **canary_meta,
    "code": request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":[address, "latest"]})["result"],
    "storage0": request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getStorageAt","params":[address, "0x0", "latest"]})["result"],
    "balance": request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getBalance","params":[address, "latest"]})["result"],
    "deployerNonce": request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getTransactionCount","params":[deployer, "latest"]})["result"],
    "receipt": request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getTransactionReceipt","params":[transaction_hash]})["result"],
}
if canary["code"] != "0x60005460005260206000f3" or int(canary["storage0"], 16) != 42 or int(canary["receipt"]["status"], 16) != 1:
    raise SystemExit(f"canary continuity failure at {stage}: {canary}")
canary["deploymentBlock"] = request("http://127.0.0.1:18545", {"jsonrpc":"2.0","id":1,"method":"eth_getBlockByHash","params":[canary["receipt"]["blockHash"], False]})["result"]
evidence["canary"] = canary
pathlib.Path(run_root, f"evidence-{stage}.json").write_text(json.dumps(evidence, indent=2) + "\n")
PY
}

rm -rf "$run_root"
mkdir -p "$run_root/consensus-genesis"
(cd "$prysm_source" && "$go_binary" build -o "$run_root/deploy-canary" "$canary_source")
for node in 1 2 3 4; do
    printf 'sepehr-phase2-miner-%s' "$node" | sha256sum | cut -d' ' -f1
done >"$run_root/mining-keys.txt"
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
stop_group execution_pids

for staged_miner in 1 2 3 4; do
    if ((staged_miner > 1)); then
        stop_group execution_pids
    fi
    for node in 1 2 3 4; do
        mining=false
        if [[ "$node" -eq "$staged_miner" ]]; then
            mining=true
        fi
        peers=""
        for peer in 1 2 3 4; do
            if [[ "$peer" -ne "$node" ]]; then
                peers+="${peers:+,}${enodes[$((peer - 1))]}"
            fi
        done
        start_execution "$node" "$mining" "$peers"
    done
    for node in 1 2 3 4; do
        wait_rpc $((18544 + node))
    done
    previous_height="$(rpc 18545 eth_blockNumber '[]' | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["result"],16))')"
    if ((staged_miner == 1)); then
        "$run_root/deploy-canary" \
            http://127.0.0.1:18545 \
            0000000000000000000000000000000000000000000000000000000000000001 \
            >"$run_root/canary-deployment.json"
    fi
    wait_for_next_converged_pow_block "$previous_height"
done

stop_group execution_pids
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

wait_for_mining_handoff
verify_four_pow_miners
stop_group execution_pids
for node in 1 2 3 4; do
    mining=false
    if [[ "$node" -eq 1 ]]; then
        mining=true
    fi
    peers=""
    for peer in 1 2 3 4; do
        if [[ "$peer" -ne "$node" ]]; then
            peers+="${peers:+,}${enodes[$((peer - 1))]}"
        fi
    done
    start_execution "$node" "$mining" "$peers"
done
for node in 1 2 3 4; do
    wait_rpc $((18544 + node))
done
wait_for_pow_terminal
wait_for_execution_convergence

"$prysmctl" testnet generate-genesis \
    --chain-config-file "$consensus_config" \
    --fork altair \
    --num-validators 256 \
    --genesis-time-delay 60 \
    --output-ssz "$run_root/consensus-genesis/genesis.ssz"
start_consensus_mesh

wait_for_pos
wait_for_finality_after 0
pre_outage_epoch="$(finalized_epoch)"
pre_outage_slot="$(head_slot)"
pre_outage_execution_hash="$(rpc 18545 eth_getBlockByNumber '["latest",false]' | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["hash"])')"
write_evidence pre-outage

stop_group validator_pids
stop_group beacon_pids
stop_group execution_pids
for step in $(seq 1 12); do
    echo "consensus outage interval $step/12"
    sleep 10
done

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
sleep 20
post_restart_execution_hash="$(rpc 18545 eth_getBlockByNumber '["latest",false]' | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["hash"])')"
if [[ "$post_restart_execution_hash" != "$pre_outage_execution_hash" ]]; then
    echo "execution head changed while post-TTD mining was enabled without consensus" >&2
    exit 1
fi

recovery_mode=true
start_consensus_mesh
wait_for_finality_after "$pre_outage_epoch"
post_outage_slot="$(head_slot)"
if ((post_outage_slot <= pre_outage_slot)); then
    echo "beacon head did not advance after recovery" >&2
    exit 1
fi
write_evidence post-outage

if [[ "$partition_test" == true ]]; then
    stop_group validator_pids
    stop_group beacon_pids
    stop_group execution_pids

    for node in 1 2 3 4; do
        if ((node % 2 == 1)); then
            peer_node=$((node + 1))
        else
            peer_node=$((node - 1))
        fi
        start_execution "$node" true "${enodes[$((peer_node - 1))]}"
    done
    for node in 1 2 3 4; do
        wait_rpc $((18544 + node))
    done

    network_mode=partition
    recovery_mode=true
    start_consensus_mesh

    partition_start_slot_1="$(head_slot_for 1)"
    partition_start_slot_3="$(head_slot_for 3)"
    wait_for_head_slot_after 1 $((partition_start_slot_1 + 8))
    wait_for_head_slot_after 3 $((partition_start_slot_3 + 8))
    partition_checkpoint_1="$(finalized_checkpoint_for 1)"
    partition_checkpoint_3="$(finalized_checkpoint_for 3)"
    partition_observation_slot_1="$(head_slot_for 1)"
    partition_observation_slot_3="$(head_slot_for 3)"

    wait_for_head_slot_after 1 $((partition_observation_slot_1 + 64))
    wait_for_head_slot_after 3 $((partition_observation_slot_3 + 64))
    partition_end_checkpoint_1="$(finalized_checkpoint_for 1)"
    partition_end_checkpoint_3="$(finalized_checkpoint_for 3)"
    if [[ "$partition_end_checkpoint_1" != "$partition_checkpoint_1" ]] \
        || [[ "$partition_end_checkpoint_3" != "$partition_checkpoint_3" ]] \
        || [[ "$partition_end_checkpoint_1" != "$partition_end_checkpoint_3" ]]; then
        echo "2/2 partition advanced or disagreed on finalized state" >&2
        exit 1
    fi

    partition_end_slot_1="$(head_slot_for 1)"
    partition_end_slot_3="$(head_slot_for 3)"
    stop_group validator_pids
    stop_group beacon_pids
    stop_group execution_pids

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

    network_mode=full
    start_consensus_mesh
    partition_epoch="${partition_end_checkpoint_1%%:*}"
    wait_for_finalized_convergence_after "$partition_epoch"
    write_evidence post-partition

    python3 - "$run_root" \
        "$partition_start_slot_1" "$partition_start_slot_3" \
        "$partition_observation_slot_1" "$partition_observation_slot_3" \
        "$partition_end_slot_1" "$partition_end_slot_3" \
        "$partition_checkpoint_1" "$partition_checkpoint_3" \
        "$partition_end_checkpoint_1" "$partition_end_checkpoint_3" <<'PY'
import json
import pathlib
import sys

(
    run_root,
    start_slot_1,
    start_slot_3,
    observation_slot_1,
    observation_slot_3,
    end_slot_1,
    end_slot_3,
    checkpoint_1,
    checkpoint_3,
    end_checkpoint_1,
    end_checkpoint_3,
) = sys.argv[1:]

evidence = {
    "topology": [[1, 2], [3, 4]],
    "validatorsPerPartition": 128,
    "startSlots": {"partition12": int(start_slot_1), "partition34": int(start_slot_3)},
    "observationStartSlots": {"partition12": int(observation_slot_1), "partition34": int(observation_slot_3)},
    "endSlots": {"partition12": int(end_slot_1), "partition34": int(end_slot_3)},
    "observationSlotsRequired": 64,
    "settledCheckpoints": {"partition12": checkpoint_1, "partition34": checkpoint_3},
    "endCheckpoints": {"partition12": end_checkpoint_1, "partition34": end_checkpoint_3},
    "safeHalt": True,
    "healedEvidence": "evidence-post-partition.json",
}
pathlib.Path(run_root, "evidence-partition.json").write_text(json.dumps(evidence, indent=2) + "\n")
PY
fi

echo "transition and equal-head outage recovery passed: $run_root"
