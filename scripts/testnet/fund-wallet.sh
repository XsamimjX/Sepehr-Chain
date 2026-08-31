#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "usage: fund-wallet.sh <wallet-address>" >&2
    exit 64
fi

: "${SEPEHR_RPC_URL:?SEPEHR_RPC_URL is required}"
: "${FAUCET_KEYSTORE:?FAUCET_KEYSTORE is required}"
: "${FAUCET_PASSWORD_FILE:?FAUCET_PASSWORD_FILE is required}"

amount="${FAUCET_AMOUNT_SEP:-200}"
if [[ ! "$amount" =~ ^[1-9][0-9]*$ ]] || (( amount > 200 )); then
    echo "FAUCET_AMOUNT_SEP must be an integer from 1 through 200" >&2
    exit 64
fi

cast send "$1" \
    --value "${amount}ether" \
    --rpc-url "$SEPEHR_RPC_URL" \
    --keystore "$FAUCET_KEYSTORE" \
    --password-file "$FAUCET_PASSWORD_FILE"
