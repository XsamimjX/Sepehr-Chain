#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

die() { printf 'error: %s\n' "$*" >&2; exit 64; }
info() { printf '[sepehr] %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

usage() {
    cat <<'EOF'
Sepehr Testnet community node helper

  sepehr-node.sh doctor
  sepehr-node.sh create [options]
  sepehr-node.sh join [options]
  sepehr-node.sh start|stop|restart|status

Create options:
  --faucet ADDRESS             Repeat exactly four times
  --execution-bootnode ENODE   Repeat at least twice
  --consensus-bootnode ENR     Repeat at least twice
  --genesis-ssz FILE
  --nethermind-bin FILE
  --beacon-bin FILE
  --validator-bin FILE
  --output FILE.tar.gz

Join options:
  --bundle FILE_OR_HTTPS_URL
  --bundle-sha256 SHA256       Required for HTTPS; local .sha256 is accepted
  --external-ip PUBLIC_IP
  --role full|validator
  --fee-recipient ADDRESS      Required for validator
  --validator-wallet DIR       Required for validator; copied with mode 0700
  --wallet-password-file FILE  Required for validator; copied with mode 0600
  --install-root DIR           Default: /opt/sepehr
  --no-systemd                 Prepare files without installing services

The public bundle never contains faucet keys, validator keys, JWT secrets, or passwords.
EOF
}

doctor() {
    local failed=0
    for command_name in bash python3 openssl sha256sum tar curl; do
        if command -v "$command_name" >/dev/null 2>&1; then
            printf 'PASS  %s\n' "$command_name"
        else
            printf 'FAIL  %s\n' "$command_name"
            failed=1
        fi
    done
    [[ "$(uname -s)" == Linux ]] || { printf 'FAIL  Linux is required for node installation\n'; failed=1; }
    if (( failed )); then
        exit 1
    fi
    python3 "$script_dir/verify-network.py"
}

create_bundle() {
    need python3; need sha256sum; need tar
    local -a faucets=() execution_bootnodes=() consensus_bootnodes=()
    local genesis_ssz='' nethermind_bin='' beacon_bin='' validator_bin='' output=''
    while (($#)); do
        case "$1" in
            --faucet) faucets+=("${2:?}"); shift 2 ;;
            --execution-bootnode) execution_bootnodes+=("${2:?}"); shift 2 ;;
            --consensus-bootnode) consensus_bootnodes+=("${2:?}"); shift 2 ;;
            --genesis-ssz) genesis_ssz="${2:?}"; shift 2 ;;
            --nethermind-bin) nethermind_bin="${2:?}"; shift 2 ;;
            --beacon-bin) beacon_bin="${2:?}"; shift 2 ;;
            --validator-bin) validator_bin="${2:?}"; shift 2 ;;
            --output) output="${2:?}"; shift 2 ;;
            *) die "unknown create option: $1" ;;
        esac
    done
    [[ ${#faucets[@]} -eq 4 ]] || die 'create requires exactly four --faucet values'
    [[ ${#execution_bootnodes[@]} -ge 2 ]] || die 'create requires at least two execution bootnodes'
    [[ ${#consensus_bootnodes[@]} -ge 2 ]] || die 'create requires at least two consensus bootnodes'
    for path in "$genesis_ssz" "$nethermind_bin" "$beacon_bin" "$validator_bin"; do
        [[ -f "$path" ]] || die "required file not found: $path"
    done
    [[ "$output" == *.tar.gz ]] || die '--output must end with .tar.gz'
    [[ ! -e "$output" ]] || die "output already exists: $output"

    local stage
    stage="$(mktemp -d)"
    trap "rm -rf '$stage'" EXIT
    mkdir -p "$stage/sepehr-testnet/bin" "$stage/sepehr-testnet/config"
    local -a render_args=()
    for address in "${faucets[@]}"; do render_args+=(--faucet-address "$address"); done
    for enode in "${execution_bootnodes[@]}"; do render_args+=(--execution-bootnode "$enode"); done
    python3 "$script_dir/render-network.py" "${render_args[@]}" --output "$stage/sepehr-testnet/config/execution-nethermind.json"
    cp "$repo_root/config/testnet/consensus.yaml" "$stage/sepehr-testnet/config/"
    cp "$repo_root/config/testnet/network-manifest.json" "$stage/sepehr-testnet/config/"
    cp "$repo_root/config/testnet/node-public-low-resource.json" "$stage/sepehr-testnet/config/node.json"
    cp "$genesis_ssz" "$stage/sepehr-testnet/config/genesis.ssz"
    cp "$nethermind_bin" "$stage/sepehr-testnet/bin/nethermind"
    cp "$beacon_bin" "$stage/sepehr-testnet/bin/beacon-chain"
    cp "$validator_bin" "$stage/sepehr-testnet/bin/validator"
    printf '%s\n' "${consensus_bootnodes[@]}" > "$stage/sepehr-testnet/config/consensus-bootnodes.txt"
    chmod 0755 "$stage/sepehr-testnet/bin/"*
    (cd "$stage/sepehr-testnet" && find bin config -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    mkdir -p "$(dirname "$output")"
    tar -C "$stage" -czf "$output" sepehr-testnet
    sha256sum "$output" > "$output.sha256"
    info "created public bundle: $output"
    info "created bundle checksum: $output.sha256"
}

write_runners() {
    local root="$1"
    mkdir -p "$root/run"
    cat > "$root/run/execution.sh" <<EOF
#!/usr/bin/env bash
exec "$root/bin/nethermind" --config "$root/config/node.json" --Init.ChainSpecPath "$root/config/execution-nethermind.json" --Init.DataDir "$root/data/execution" --Init.BaseDbPath "$root/data/execution/db" --Init.LogDirectory "$root/log/execution" --JsonRpc.JwtSecretFile "$root/secrets/jwt.hex" --Network.ExternalIp "\${SEPEHR_EXTERNAL_IP:?}" --Network.LocalIp 0.0.0.0
EOF
    cat > "$root/run/beacon.sh" <<EOF
#!/usr/bin/env bash
args=()
while IFS= read -r enr; do [[ -n "\$enr" ]] && args+=(--bootstrap-node "\$enr"); done < "$root/config/consensus-bootnodes.txt"
exec "$root/bin/beacon-chain" --accept-terms-of-use --chain-config-file "$root/config/consensus.yaml" --datadir "$root/data/beacon" --genesis-state "$root/config/genesis.ssz" --execution-endpoint http://127.0.0.1:8551 --jwt-secret "$root/secrets/jwt.hex" --rpc-host 127.0.0.1 --rpc-port 4000 --http-host 127.0.0.1 --http-port 3500 --p2p-host-ip "\${SEPEHR_EXTERNAL_IP:?}" --p2p-tcp-port 13000 --p2p-udp-port 12000 --disable-quic "\${args[@]}"
EOF
    cat > "$root/run/validator.sh" <<EOF
#!/usr/bin/env bash
exec "$root/bin/validator" --accept-terms-of-use --chain-config-file "$root/config/consensus.yaml" --datadir "$root/data/validator" --wallet-dir "$root/secrets/validator-wallet" --wallet-password-file "$root/secrets/wallet-password.txt" --beacon-rpc-provider 127.0.0.1:4000 --beacon-rest-api-provider http://127.0.0.1:3500 --suggested-fee-recipient "\${SEPEHR_FEE_RECIPIENT:?}" --disable-monitoring
EOF
    chmod 0755 "$root/run/"*.sh
}

install_units() {
    local root="$1" role="$2"
    [[ $EUID -eq 0 ]] || die 'systemd installation requires sudo/root; use --no-systemd for preparation only'
    command -v systemctl >/dev/null 2>&1 || die 'systemctl not found'
    id sepehr >/dev/null 2>&1 || useradd --system --home "$root" --shell /usr/sbin/nologin sepehr
    chown -R sepehr:sepehr "$root"
    for service in execution beacon; do
        cat > "/etc/systemd/system/sepehr-$service.service" <<EOF
[Unit]
Description=Sepehr Testnet $service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sepehr
Group=sepehr
EnvironmentFile=$root/config/node.env
ExecStart=$root/run/$service.sh
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    done
    if [[ "$role" == validator ]]; then
        cat > /etc/systemd/system/sepehr-validator.service <<EOF
[Unit]
Description=Sepehr Testnet validator
After=sepehr-beacon.service
Requires=sepehr-beacon.service

[Service]
Type=simple
User=sepehr
Group=sepehr
EnvironmentFile=$root/config/node.env
ExecStart=$root/run/validator.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload
    systemctl enable sepehr-execution sepehr-beacon
    [[ "$role" == validator ]] && systemctl enable sepehr-validator
}

join_network() {
    need python3; need sha256sum; need tar; need openssl
    local bundle='' expected='' external_ip='' role='full' fee_recipient=''
    local validator_wallet='' password_file='' install_root='/opt/sepehr' systemd=true
    while (($#)); do
        case "$1" in
            --bundle) bundle="${2:?}"; shift 2 ;;
            --bundle-sha256) expected="${2:?}"; shift 2 ;;
            --external-ip) external_ip="${2:?}"; shift 2 ;;
            --role) role="${2:?}"; shift 2 ;;
            --fee-recipient) fee_recipient="${2:?}"; shift 2 ;;
            --validator-wallet) validator_wallet="${2:?}"; shift 2 ;;
            --wallet-password-file) password_file="${2:?}"; shift 2 ;;
            --install-root) install_root="${2:?}"; shift 2 ;;
            --no-systemd) systemd=false; shift ;;
            *) die "unknown join option: $1" ;;
        esac
    done
    [[ -n "$bundle" && -n "$external_ip" ]] || die 'join requires --bundle and --external-ip'
    [[ "$external_ip" =~ ^[0-9A-Fa-f:.]+$ ]] || die '--external-ip contains invalid characters'
    [[ "$role" == full || "$role" == validator ]] || die '--role must be full or validator'
    [[ "$install_root" == /* && "$install_root" != / ]] || die '--install-root must be an absolute non-root path'
    if [[ "$role" == validator ]]; then
        [[ "$fee_recipient" =~ ^0x[0-9a-fA-F]{40}$ ]] || die 'validator requires a valid --fee-recipient'
        [[ -d "$validator_wallet" && -f "$password_file" ]] || die 'validator wallet directory and password file are required'
    fi
    local temp bundle_file
    temp="$(mktemp -d)"; trap "rm -rf '$temp'" EXIT
    if [[ "$bundle" =~ ^https:// ]]; then
        need curl
        [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die 'HTTPS bundle requires --bundle-sha256'
        bundle_file="$temp/network.tar.gz"
        curl --fail --location --proto '=https' --tlsv1.2 "$bundle" --output "$bundle_file"
    else
        bundle_file="$(realpath "$bundle")"
        [[ -f "$bundle_file" ]] || die "bundle not found: $bundle"
        if [[ -z "$expected" && -f "$bundle_file.sha256" ]]; then expected="$(awk '{print $1}' "$bundle_file.sha256")"; fi
        [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die 'local bundle requires --bundle-sha256 or a matching .sha256 file'
    fi
    printf '%s  %s\n' "$expected" "$bundle_file" | sha256sum --check --status || die 'bundle SHA-256 mismatch'
    python3 - "$bundle_file" <<'PY'
import pathlib
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    for member in archive.getmembers():
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "sepehr-testnet":
            raise SystemExit(f"unsafe bundle path: {member.name}")
        if member.issym() or member.islnk() or member.isdev():
            raise SystemExit(f"links and device entries are not allowed: {member.name}")
PY
    tar -xzf "$bundle_file" -C "$temp"
    (cd "$temp/sepehr-testnet" && sha256sum --check SHA256SUMS)
    [[ ! -e "$install_root" ]] || die "install root already exists: $install_root"
    mkdir -p "$install_root" "$install_root/data" "$install_root/log" "$install_root/secrets"
    cp -a "$temp/sepehr-testnet/bin" "$temp/sepehr-testnet/config" "$install_root/"
    umask 077; openssl rand -hex 32 > "$install_root/secrets/jwt.hex"
    printf 'SEPEHR_EXTERNAL_IP=%s\nSEPEHR_FEE_RECIPIENT=%s\n' "$external_ip" "$fee_recipient" > "$install_root/config/node.env"
    if [[ "$role" == validator ]]; then
        cp -a "$validator_wallet" "$install_root/secrets/validator-wallet"
        cp "$password_file" "$install_root/secrets/wallet-password.txt"
        chmod -R go-rwx "$install_root/secrets"
    fi
    write_runners "$install_root"
    if [[ "$systemd" == true ]]; then install_units "$install_root" "$role"; fi
    info "node prepared at $install_root"
    info "run: $0 start"
}

lifecycle() {
    local action="$1"
    command -v systemctl >/dev/null 2>&1 || die 'systemctl is required for lifecycle commands'
    local -a units=(sepehr-execution sepehr-beacon)
    systemctl list-unit-files sepehr-validator.service >/dev/null 2>&1 && units+=(sepehr-validator)
    case "$action" in
        start|stop|restart)
            if [[ $EUID -eq 0 ]]; then systemctl "$action" "${units[@]}"; else sudo systemctl "$action" "${units[@]}"; fi
            ;;
        status) systemctl --no-pager --full status "${units[@]}" ;;
    esac
}

command_name="${1:-}"
shift || true
case "$command_name" in
    doctor) doctor "$@" ;;
    create) create_bundle "$@" ;;
    join) join_network "$@" ;;
    start|stop|restart|status) lifecycle "$command_name" ;;
    -h|--help|help|'') usage ;;
    *) usage >&2; die "unknown command: $command_name" ;;
esac
