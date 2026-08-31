# Sepehr Testnet artifact states

- `execution-nethermind.template.json`: tracked input with a faucet placeholder.
- `execution-nethermind.json`: generated canonical execution genesis; create only with real bootnode identities and the offline faucet public address.
- `consensus.yaml`: tracked consensus parameters.
- `genesis.ssz`: generated canonical consensus genesis; create only from the real, non-overlapping validator set.
- `network-manifest.json`: public network properties and resource profile.
- `node-public-low-resource.json`: constrained node configuration, not an archive/public-RPC profile.

Never invent bootnode identities, validator keys, faucet addresses, or genesis hashes. Before launch, publish a signed checksum manifest covering the execution genesis, consensus genesis, client builds, and configuration files.
