# Sepehr Chain

This is the independent Sepehr execution/consensus client repository.

It contains pinned chain specifications, client patches, transition scripts, provenance, and reproducible Phase 2 evidence. Generated client source checkouts, binaries, node databases, validator wallets, JWT files, and secrets are intentionally ignored.

The current scripts under `scripts/phase2/` are single-machine research and recovery harnesses. They are not a four-VPS installer. Do not expose their RPC, Engine API, validator API, or PoW network publicly.

Before the experimental four-host testnet can be installed, Phase 10 must add and verify:

- Four-host WireGuard inventory and firewall rules.
- Reproducible patched Nethermind and Prysm builds.
- A single signed EL/CL genesis bundle and checksum manifest.
- Four non-overlapping 64-validator encrypted key bundles.
- Per-host systemd units and environment files.
- Bootnode/static-peer configuration.
- Backup, slashing-protection, restore, partition, and outage procedures.
- A private soak test before public RPC is enabled after the Merge.

Tracked evidence JSON is safe to publish only after checking it contains no secrets. Runtime logs, PID files, binaries, databases, wallets, and secrets must remain outside Git.
