# Sepehr Chain | زنجیره سپهر

[English](#english) · [فارسی](#فارسی)

Repository: <https://github.com/XsamimjX/Sepehr-Chain>

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

### Join the network as a community member

You do not create a new genesis when joining. Download the release bundle URL and SHA-256 published by the Sepehr maintainers, then run:

```bash
git clone https://github.com/XsamimjX/Sepehr-Chain.git
cd Sepehr-Chain
./scripts/testnet/sepehr-node.sh doctor
sudo ./scripts/testnet/sepehr-node.sh join \
  --bundle https://RELEASE_URL/sepehr-testnet.tar.gz \
  --bundle-sha256 PUBLISHED_64_CHARACTER_SHA256 \
  --external-ip YOUR_PUBLIC_IPV4 \
  --role full
sudo ./scripts/testnet/sepehr-node.sh start
./scripts/testnet/sepehr-node.sh status
```

Before joining, open TCP/UDP `30303`, TCP `13000`, and UDP `12000` in the VPS firewall and provider firewall. Do not open `8551`, `4000`, or `3500`. Compare the bundle checksum with a second official channel. A normal full node needs no validator or faucet key.

To become a validator, first coordinate with maintainers so you receive a unique validator allocation and slashing-protection record. Never reuse validator keys on two machines:

```bash
sudo ./scripts/testnet/sepehr-node.sh join \
  --bundle /path/to/sepehr-testnet.tar.gz \
  --external-ip YOUR_PUBLIC_IPV4 \
  --role validator \
  --fee-recipient 0xYOUR_PUBLIC_REWARD_ADDRESS \
  --validator-wallet /secure/path/to/your-wallet \
  --wallet-password-file /secure/path/to/password.txt
```

The helper verifies the outer bundle hash and every bundled file, creates a node-local JWT, keeps APIs on loopback, installs systemd services, and never downloads validator secrets from the public bundle.

### Finalize the immutable execution genesis

Create four faucet accounts offline—one for each initial operator—and retain only their public addresses in genesis. Keep encrypted keystores and passwords outside Git. Maintainers normally use the one-command bundle builder:

```bash
./scripts/testnet/sepehr-node.sh create \
  --faucet 0xNODE_1_FAUCET \
  --faucet 0xNODE_2_FAUCET \
  --faucet 0xNODE_3_FAUCET \
  --faucet 0xNODE_4_FAUCET \
  --execution-bootnode enode://NODE_1_PUBLIC_KEY@VPS_1_IP:30303 \
  --execution-bootnode enode://NODE_2_PUBLIC_KEY@VPS_2_IP:30303 \
  --consensus-bootnode enr:NODE_1_ENR \
  --consensus-bootnode enr:NODE_2_ENR \
  --genesis-ssz /secure/build/genesis.ssz \
  --nethermind-bin artifacts/nethermind/nethermind \
  --beacon-bin artifacts/prysm/beacon-chain \
  --validator-bin artifacts/prysm/validator \
  --output release/sepehr-testnet.tar.gz
```

The resulting file is immutable once the network starts. Distribute the exact same file and SHA-256 digest to every host. The consensus genesis must then be generated from the 256 real validator deposits and use the execution genesis hash; the template is not launch-ready until that `genesis.ssz`, its bootstrap ENRs, and the checksum manifest exist.

### Fund a test wallet

Genesis assigns 1,000,000 valueless test SEP to each of four node-operated faucets. Each accepted wallet request receives 200 SEP by default:

```bash
export SEPEHR_RPC_URL=http://127.0.0.1:8545
export FAUCET_KEYSTORE=/var/lib/sepehr-faucet/keystore/UTC--...
export FAUCET_PASSWORD_FILE=/etc/sepehr/secrets/faucet-password
scripts/testnet/fund-wallet.sh 0xRECIPIENT_ADDRESS
```

The script caps one transfer at 200 SEP and does not put the private key on the command line. It is an operator funding path, not yet a public Sepolia-style web faucet. A public faucet still requires PostgreSQL-backed address/IP limits, abuse controls, signer isolation, monitoring, and tests before exposure.

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

مخزن رسمی: <https://github.com/XsamimjX/Sepehr-Chain>

### پیوستن یک عضو جامعه به شبکه

برای پیوستن، genesis جدید نسازید. آدرس بسته رسمی و SHA-256 آن را از انتشار رسمی دریافت کنید و مراحل زیر را انجام دهید:

```bash
git clone https://github.com/XsamimjX/Sepehr-Chain.git
cd Sepehr-Chain
./scripts/testnet/sepehr-node.sh doctor
sudo ./scripts/testnet/sepehr-node.sh join \
  --bundle https://RELEASE_URL/sepehr-testnet.tar.gz \
  --bundle-sha256 PUBLISHED_SHA256 \
  --external-ip YOUR_PUBLIC_IPV4 \
  --role full
sudo ./scripts/testnet/sepehr-node.sh start
./scripts/testnet/sepehr-node.sh status
```

در فایروال TCP/UDP پورت `30303`،‏ TCP پورت `13000` و UDP پورت `12000` را باز کنید. پورت‌های `8551`،‏ `4000` و `3500` را عمومی نکنید. یک full node عادی به کلید اعتبارسنج یا faucet نیاز ندارد. برای validator شدن باید ابتدا از نگهدارندگان سهم کلید منحصربه‌فرد و slashing protection بگیرید؛ یک کلید را هم‌زمان روی دو سرور اجرا نکنید.

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

Genesis به هر یک از چهار faucet اولیه 1,000,000 SEP آزمایشی و بدون ارزش اختصاص می‌دهد و مقدار پیش‌فرض هر درخواست پذیرفته‌شده 200 SEP است. `scripts/testnet/fund-wallet.sh` مسیر پرداخت اپراتوری است و کلید خصوصی را در آرگومان قرار نمی‌دهد. faucet عمومی مشابه Sepolia هنوز به محدودیت آدرس/IP در PostgreSQL، جداسازی signer، کنترل سوءاستفاده، مانیتورینگ و آزمون نیاز دارد.

### منابع و امنیت

پروفایل 2 هسته، 4 گیگابایت رم و 30 گیگابایت NVMe فقط برای گره کوچک، pruned، بدون archive و بدون RPC عمومی آزمایشی است. پذیرش آن منوط به آزمون sync، گذار، رشد دیسک، pruning و soak هفت‌روزه روی همان VPS است. سپهربین، PostgreSQL، RPC عمومی یا archive را روی این اندازه اجرا نکنید.

هیچ کلید، JWT، رمز، کیف اعتبارسنج، slashing database یا `.env` را commit نکنید. هر میزبان باید genesis عمومی یکسان، ولی هویت گره و 64 کلید اعتبارسنج منحصربه‌فرد داشته باشد.
