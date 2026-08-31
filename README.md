# Sepehr Chain | زنجیره سپهر

[English](#english) · [فارسی](#فارسی)

## English

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

## Dependencies and source setup

- Ubuntu Linux or WSL2 for the verified build path.
- Git, Python 3, Bash, `curl`, `jq`, `openssl`, and standard build tools.
- .NET SDK 10.0.100 or newer for pinned Nethermind 1.39.2; the recorded build used 10.0.400.
- Go matching the pinned Prysm `go.mod`. Use the exact compatible toolchain recorded in `provenance.json`; a newer Go release is not automatically compatible.
- Foundry `cast` for the operator faucet command.

Execution and consensus clients retain their required native databases. PostgreSQL is for Raygir, a future public faucet service, and Sepehrbin—not for the node database.

Clone this independent repository and initialize upstream sources using its pinned commits, provenance, and patches. Do not build a canonical network from an unpinned “latest” client. Verify commit signatures and the checksums of every patch, binary, configuration, and genesis artifact before distribution.

Configuration validation:

```bash
python3 scripts/testnet/verify-network.py
bash -n scripts/testnet/fund-wallet.sh
```

The current `scripts/phase2/` commands are research harnesses, not four-VPS installers. Before persistent launch, generate real bootnode identities, an offline faucet address, 256 non-overlapping validator keys, `execution-nethermind.json`, `genesis.ssz`, and a signed artifact manifest. Every host receives identical public genesis artifacts but distinct node secrets and 64 distinct validator keys.

---

## فارسی

زنجیره سپهر مخزن مستقل کلاینت اجرایی/اجماع، وصله‌های پژوهشی، تنظیمات گذار اثبات کار به اثبات سهام و شواهد قابل‌بازسازی است. تست‌نت سپهر مانند یک شبکه پایدار و اصلی رفتار می‌کند، اما همه دارایی‌های آن فاقد ارزش و غیرقابل بازخرید هستند؛ این شبکه مین‌نت سپهر نیست.

### ارتباط همتاها

Nethermind با رکوردهای عمومی `enode` و discv4/discv5 همتاها را پیدا می‌کند. Prysm نیز از ENRهای bootstrap و discv5/libp2p استفاده می‌کند. WireGuard برای P2P الزامی نیست و peer ثابت فقط مسیر بازیابی است.

TCP و UDP پورت `30303` برای execution،‏ TCP پورت `13000` و UDP پورت `12000` برای consensus باید باز باشند. Engine API روی `8551`،‏ API اعتبارسنج، JWT،‏ keystore و فایل رمز هرگز نباید عمومی شوند.

### پیش‌نیازها

- Ubuntu Linux یا WSL2 برای مسیر ساخت آزموده‌شده.
- Git،‏ Python 3،‏ Bash،‏ `curl`،‏ `jq`،‏ `openssl` و ابزارهای ساخت.
- .NET SDK حداقل 10.0.100 برای Nethermind پین‌شده؛ ساخت ثبت‌شده با 10.0.400 انجام شده است.
- نسخه Go سازگار با `go.mod` نسخه پین‌شده Prysm و اطلاعات `provenance.json`؛ نسخه جدیدتر الزاماً سازگار نیست.
- ابزار `cast` از Foundry برای انتقال faucet.

گره‌ها پایگاه‌داده داخلی لازم کلاینت را دارند و از PostgreSQL استفاده نمی‌کنند. رای‌گیر، faucet عمومی آینده و سپهربین باید PostgreSQL مستقل داشته باشند.

این مخزن را جداگانه clone کنید و upstreamها را فقط از commitهای ثبت‌شده و با وصله‌های همین مخزن بسازید. برای شبکه canonical از نسخه `latest` استفاده نکنید. امضا و checksum تمام commitها، وصله‌ها، باینری‌ها، تنظیمات و فایل‌های genesis را کنترل کنید.

```bash
python3 scripts/testnet/verify-network.py
bash -n scripts/testnet/fund-wallet.sh
```

### ساخت شبکه و faucet

حساب faucet را آفلاین بسازید و فقط آدرس عمومی آن را در genesis قرار دهید. با `scripts/testnet/render-network.py` و حداقل دو `enode` واقعی فایل `execution-nethermind.json` را بسازید. پس از شروع شبکه این فایل تغییرپذیر نیست. سپس از 256 کلید واقعی و بدون هم‌پوشانی، فایل `genesis.ssz` نهایی را بسازید.

Genesis یک میلیارد SEP آزمایشی و بدون ارزش به faucet اختصاص می‌دهد. `scripts/testnet/fund-wallet.sh` مسیر پرداخت اپراتوری است و کلید خصوصی را در آرگومان قرار نمی‌دهد. faucet عمومی مشابه Sepolia هنوز به محدودیت آدرس/IP در PostgreSQL، جداسازی signer، کنترل سوءاستفاده، مانیتورینگ و آزمون نیاز دارد.

### منابع و امنیت

پروفایل 2 هسته، 4 گیگابایت رم و 30 گیگابایت NVMe فقط برای گره کوچک، pruned، بدون archive و بدون RPC عمومی آزمایشی است. پذیرش آن منوط به آزمون sync، گذار، رشد دیسک، pruning و soak هفت‌روزه روی همان VPS است. سپهربین، PostgreSQL، RPC عمومی یا archive را روی این اندازه اجرا نکنید.

هیچ کلید، JWT، رمز، کیف اعتبارسنج، slashing database یا `.env` را commit نکنید. هر میزبان باید genesis عمومی یکسان، ولی هویت گره و 64 کلید اعتبارسنج منحصربه‌فرد داشته باشد.
