# Aptos Red Packet
Red packets implemented using the Move programming language

A red packet social application that combines the privacy chat on ComingChat and the omnichain wallet on ComingChat.

The code contract will be deployed to the Aptos smart contract platform

### Supported dependencies
- aptos-cli: `Aptos CLI Release v1.0.0`
- AptosFramework: `main @ 01108a2345b87d539d54a67b32db55193f9ace40`
- AptosStdlib: `main @ 01108a2345b87d539d54a67b32db55193f9ace40`

### Roles and Calls
- `owner`: `publish`, `initialize`, `set_admin`, `set_fee_point`
- `admin`: `register_coin`, `open`, `close`, `batch_close`, `set_base_prepaid_fee`
- `user`: `create`

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
git checkout a5ac706f74c3b5088649e744b76ec6ed32635c0d

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

### bench data
```txt
create(after 150,000 items): 445~725 gas
open(max=1000 items): 64544 gas
batch_close(10000 items): 464853 gas
```

### test cmds
test coins
```move
module mycoin::Coins {
    /// Coin define
    ////////////////////////
    struct TestCoin {}

    struct XBTC {}

    struct XETH {}

    struct XDOT {}
    ////////////////////////
}
```

```bash
# publish mycoin
aptos move publish \
    --named-addresses mycoin=0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0

# issue coins
aptos move run \
    --function-id 0x1::managed_coin::initialize \
    --args string:"Test" string:"Test" u8:8 bool:true \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::initialize \
    --args string:"XBTC" string:"XBTC" u8:8 bool:true \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XBTC \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::initialize \
    --args string:"XETH" string:"XETH" u8:8 bool:true \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XETH \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::initialize \
    --args string:"XDOT" string:"XDOT" u8:8 bool:true \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XDOT \
    --assume-yes

# register account
aptos move run \
    --function-id 0x1::managed_coin::register \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::register \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XBTC \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::register \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XETH \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::register \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XDOT \
    --assume-yes

# mint coins
aptos move run \
    --function-id 0x1::managed_coin::mint \
    --args address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0 u64:10000000000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::mint \
    --args address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0 u64:10000000000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XBTC \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::mint \
    --args address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0 u64:10000000000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XETH \
    --assume-yes

aptos move run \
    --function-id 0x1::managed_coin::mint \
    --args address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0 u64:10000000000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XDOT \
    --assume-yes

==================================================================================================

# publish red-packet
aptos move publish --named-addresses RedPacket=0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0

# owner red_packet::initialize
aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::initialize \
    --args address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0 \
           address:0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0

# admin red_packet::register_coin
aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::register_coin \
    --type-args 0x1::aptos_coin::AptosCoin \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::register_coin \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XBTC \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::register_coin \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XETH \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::register_coin \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XDOT \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::register_coin \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --assume-yes

# admin red_packet::create
aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create \
    --args u64:0 u64:1000 u64:10000 \
    --type-args 0x1::aptos_coin::AptosCoin \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create \
    --args u64:1 u64:1000 u64:10000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XBTC \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create \
    --args u64:2 u64:1000 u64:10000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XETH \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create \
    --args u64:3 u64:1000 u64:10000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::XDOT \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create \
    --args u64:4 u64:1000 u64:10000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --assume-yes


# bench (needs create2)
aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create2 \
    --args u64:0 u64:1000 u64:10000 u64:50000 \
    --type-args 0x1::aptos_coin::AptosCoin \
    --max-gas 4000000 \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::create2 \
    --args u64:4 u64:1000 u64:10000 u64:50000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --max-gas 4000000 \
    --assume-yes

aptos move run \
    --function-id 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::red_packet::batch_close \
    --args u64:4 u64:0 u64:10000 \
    --type-args 0xa24881e004fdbc5550932bb2879129351c21432f21f32d94bf11603bebd9f5c0::Coins::TestCoin \
    --max-gas 4000000 \
    --assume-yes

```
