#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <phase2-genesis-dir> <output-dir>" >&2
    exit 64
fi

genesis_dir="$(realpath "$1")"
output_dir="$(realpath -m "$2")"
validator_bin="$(realpath "$(dirname "$0")/../../artifacts/prysm/validator-linux-amd64")"

if [[ "$output_dir" == "/" || "$output_dir" == "$genesis_dir" ]]; then
    echo "refusing unsafe output directory: $output_dir" >&2
    exit 64
fi

mkdir -p "$output_dir"
empty_keys_dir="$output_dir/empty-keystores"
mkdir -p "$empty_keys_dir"
password_file="$output_dir/wallet-password.txt"
umask 077
printf '%s\n' 'sepehr-phase2-research-only' > "$password_file"

for node in 1 2 3 4; do
    wallet_dir="$output_dir/wallet-node-$node"
    keys_json="$genesis_dir/node-$node-keys.json"
    if [[ "$wallet_dir" != "$output_dir"/* ]]; then
        echo "refusing wallet path outside output directory: $wallet_dir" >&2
        exit 64
    fi
    rm -rf "$wallet_dir"

    "$validator_bin" wallet create \
        --wallet-dir "$wallet_dir" \
        --keymanager-kind imported \
        --wallet-password-file "$password_file" \
        --accept-terms-of-use

    mapfile -t private_keys < <(python3 - "$keys_json" <<'PY'
import base64
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    for key in json.load(source)["keys"]:
        print(base64.b64decode(key["validator_key"]).hex())
PY
    )
    for private_key in "${private_keys[@]}"; do
        key_file="$(mktemp)"
        trap 'rm -f "$key_file"' EXIT
        chmod 600 "$key_file"
        printf '%s\n' "$private_key" > "$key_file"
        "$validator_bin" accounts import \
            --wallet-dir "$wallet_dir" \
            --wallet-password-file "$password_file" \
            --keys-dir "$empty_keys_dir" \
            --import-private-key-file "$key_file" \
            --accept-terms-of-use </dev/null
        rm -f "$key_file"
        trap - EXIT
    done
done

chmod 600 "$password_file"
