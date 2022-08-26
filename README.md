# Red Packet
Red packets implemented using the Move programming language

A red packet social application that combines the privacy chat on ComingChat and the omnichain wallet on ComingChat.

The code contract will be deployed to the Aptos/Sui smart contract platform

### Supported dependencies
- aptos-cli: `Aptos CLI Release v0.3.1`
- AptosFramework: `main @ 2c1e2dd5be5c71dd8069c7a6382d9f911a1cd5d0`
- AptosStdlib: `main @ 2c1e2dd5be5c71dd8069c7a6382d9f911a1cd5d0`

### Install
```bash
# aptos-cli
Install Aptos CLI
https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli

# red-packet
git clone https://github.com/coming-chat/red-packet.git
cd red-packet

# aptos-core
git clone https://github.com/aptos-labs/aptos-core.git
cd aptos-core
git checkout 2c1e2dd5be5c71dd8069c7a6382d9f911a1cd5d0

# red-packet tree

├── aptos-core
├── build
├── LICENSE
├── Move.toml
├── README.md
└── sources
```

### Compile & Test & Publish
run `aptos init` in `red-packet` to config aptos network environment

example result
```bash
 cd red-packet
 cat .aptos/config.yaml 
---
profiles:
  default:
    private_key: <your privkey>
    public_key: <your pubkey>
    account: <your address>
    rest_url: "https://fullnode.devnet.aptoslabs.com/v1"
    faucet_url: "https://faucet.devnet.aptoslabs.com/"

```

```bash
aptos move compile --named-addresses RedPacket=<your address>

aptos move test

aptos move publish --named-addresses RedPacket=<your address>
```
