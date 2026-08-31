# Sepehr Chain

This independent repository contains the Sepehr execution/consensus client configuration, client patches, transition tooling, and reproducible evidence.

## Sepehr Testnet

`config/testnet/` defines the persistent, public-discovery research network. It behaves like a canonical network, but every asset is explicitly valueless and non-redeemable. It is not Sepehr mainnet.

Nodes discover peers over the normal Ethereum networking stack:

- Nethermind uses public execution bootnode `enode` records and discv4/discv5 peer discovery.
- Prysm uses public bootstrap ENRs and discv5/libp2p peer discovery.
- Static peers are a recovery option, not the normal topology.
- WireGuard is not required for node-to-node P2P.

Open TCP and UDP `30303` for execution P2P, TCP `13000` and UDP `12000` for consensus P2P. Never expose the Engine API on `8551`, Prysm validator API, JWT secret, keystores, or password files. Public JSON-RPC remains disabled during PoW and until the post-Merge gates pass.

At least two stable execution bootnodes and two stable consensus bootstrap nodes are required. Bootnodes introduce peers; after discovery, nodes connect and gossip directly.

### Finalize the immutable execution genesis

Create the faucet account offline and retain only its public address in the genesis. Keep its encrypted keystore and password file outside Git. Then render the canonical genesis with real, stable public bootnode records:

```bash
python3 scripts/testnet/render-network.py \
  --faucet-address 0xYOUR_PUBLIC_FAUCET_ADDRESS \
  --execution-bootnode enode://NODE_1_PUBLIC_KEY@VPS_1_IP:30303 \
  --execution-bootnode enode://NODE_2_PUBLIC_KEY@VPS_2_IP:30303 \
  --output config/testnet/execution-nethermind.json
```

The resulting file is immutable once the network starts. Distribute the exact same file and SHA-256 digest to every host. The consensus genesis must then be generated from the 256 real validator deposits and use the execution genesis hash; the template is not launch-ready until that `genesis.ssz`, its bootstrap ENRs, and the checksum manifest exist.

### Fund a test wallet

The genesis assigns 1,000,000,000 test SEP to the faucet address. The operator can grant 10 SEP by default:

```bash
export SEPEHR_RPC_URL=http://127.0.0.1:8545
export FAUCET_KEYSTORE=/var/lib/sepehr-faucet/keystore/UTC--...
export FAUCET_PASSWORD_FILE=/etc/sepehr/secrets/faucet-password
scripts/testnet/fund-wallet.sh 0xRECIPIENT_ADDRESS
```

The script caps one transfer at 100 SEP and does not put the private key on the command line. It is an operator funding path, not yet a public Sepolia-style web faucet. A public faucet still requires PostgreSQL-backed address/IP limits, abuse controls, signer isolation, monitoring, and tests before exposure.

### Small VPS profile

`node-public-low-resource.json` is an experimental non-archive profile for 2 vCPU, 4 GB RAM, and 30 GB NVMe. It limits peers and caches, keeps RPC private, and uses memory pruning. It may be adequate only while chain state and traffic remain very small. It must pass repeated transition, sync, pruning, disk-growth, and seven-day soak tests on the exact VPS type.

Do not use that host size for an archive node, public RPC service, Sepehrbin indexing, PostgreSQL, or co-hosted Raygir services. Those roles need separate, larger storage and memory based on measured growth.

## Safety

Generated client source checkouts, binaries, node databases, validator wallets, JWT files, faucet secrets, and other credentials are ignored. Check evidence JSON before publishing it. The existing `scripts/phase2/` harness remains a single-machine research/recovery harness and must not be exposed as a public deployment.
