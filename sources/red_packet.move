/// Copyright 2022 ComingChat Authors. Licensed under Apache-2.0 License.
module RedPacket::red_packet {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string;
    use aptos_std::event::{Self, EventHandle};
    use aptos_std::type_info;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use RedPacket::bucket_table;

    const MAX_COUNT: u64 = 1000;
    const MIN_BALANCE: u64 = 10000; // 0.0001 APT(decimals=8)
    const INIT_FEE_POINT: u8 = 250; // 2.5%
    const BASE_PREPAID_FEE: u64 = 1 * 4; // gas_price * gas_used

    const ENOT_ENOUGH_COIN: u64 = 1;
    const EREDPACKET_PERMISSION_DENIED: u64 = 2;
    const EREDPACKET_ALREADY_PUBLISHED: u64 = 3;
    const EACCOUNTS_BALANCES_LEN_MISMATCH: u64 = 4;
    const EREDPACKET_INSUFFICIENT_BALANCES: u64 = 5;
    const EREDPACKET_NOT_PUBLISHED: u64 = 6;
    const EREDPACKET_NOT_FOUND: u64 = 7;
    const EREDPACKET_TOO_MANY: u64 = 8;
    const EREDPACKET_TOO_LITTLE: u64 = 9;
    const EREDPACKET_ALREADY_REGISTER: u64 = 10;

    const EVENT_TYPE_CREATE: u8 = 0;
    const EVENT_TYPE_OPEN: u8 = 1;
    const EVENT_TYPE_CLOASE: u8 = 2;

    #[test_only]
    struct TestCoin {}

    /// Event emitted when created/opened/closed a red packet.
    struct RedPacketEvent has drop, store {
        id: u64,
        event_type: u8,
        remain_count: u64,
        remain_balance: u64
    }

    struct ConfigEvent has drop, store {
        active: Config
    }

    /// initialize when create
    /// change when open
    /// drop when close
    struct RedPacketInfo has drop, store {
        remain_coin: u64,
        remain_count: u64,
    }

    struct Config has copy, drop, store {
        beneficiary: address,
        admin: address,
        fee_point: u8,
        base_prepaid: u64,
    }

    struct RedPackets has key {
        next_id: u64,
        config: Config,
        store: bucket_table::BucketTable<u64, RedPacketInfo>,
        events: EventHandle<RedPacketEvent>,
        config_events: EventHandle<ConfigEvent>
    }

    struct Escrow<phantom CoinType> has key {
        coin: Coin<CoinType>,
    }

    public fun red_packet_address(): address {
        type_info::account_address(&type_info::type_of<RedPackets>())
    }

    /// A helper function that returns the address of CoinType.
    public fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    public fun check_operator(
        operator_address: address,
        require_admin: bool
    ) acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );
        assert!(
            !require_admin || admin() == operator_address || red_packet_address() == operator_address,
            error::permission_denied(EREDPACKET_PERMISSION_DENIED),
        );
    }

    // call by comingchat
    public entry fun initialize(
        owner: &signer,
        beneficiary: address,
        admin: address,
    ) {
        let owner_addr = signer::address_of(owner);
        assert!(
            red_packet_address() == owner_addr,
            error::permission_denied(EREDPACKET_PERMISSION_DENIED),
        );

        assert!(
            !exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_ALREADY_PUBLISHED),
        );

        let red_packets = RedPackets{
            next_id: 1,
            config: Config {
                beneficiary,
                admin,
                fee_point: INIT_FEE_POINT,
                base_prepaid: BASE_PREPAID_FEE,
            },
            store: bucket_table::new<u64, RedPacketInfo>(1),
            events: account::new_event_handle<RedPacketEvent>(owner),
            config_events: account::new_event_handle<ConfigEvent>(owner)
        };

        move_to(owner, red_packets)
    }

    public entry fun register_coin<CoinType>(
        operator: &signer,
    ) acquires RedPackets {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, false);

        assert!(
            !exists<Escrow<CoinType>>(red_packet_address()),
            error::already_exists(EREDPACKET_ALREADY_PUBLISHED),
        );

        move_to(
            operator,
            Escrow<CoinType> {
                coin: coin::zero<CoinType>()
            }
        );
    }

    // call by anyone in comingchat
    public entry fun create<CoinType>(
        operator: &signer,
        count: u64,
        total_balance: u64
    ) acquires RedPackets, Escrow {
        assert!(
            total_balance >= MIN_BALANCE,
            error::invalid_argument(EREDPACKET_TOO_LITTLE)
        );

        let operator_address = signer::address_of(operator);
        check_operator(operator_address, false);

        assert!(
            coin::balance<CoinType>(operator_address) >= total_balance,
            error::invalid_argument(ENOT_ENOUGH_COIN)
        );

        assert!(
            count <= MAX_COUNT,
            error::invalid_argument(EREDPACKET_TOO_MANY),
        );

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());

        let id = red_packets.next_id;

        let info  = RedPacketInfo {
            remain_coin: 0,
            remain_count: count,
        };

        let prepaid_fee = count * red_packets.config.base_prepaid;
        let (fee,  escrow) = calculate_fee(total_balance, red_packets.config.fee_point);
        let fee_coin = coin::withdraw<CoinType>(operator, fee);
        if (coin_address<CoinType>() == @aptos_std && coin::symbol<CoinType>() == string::utf8(b"APT")) {
            if (fee > prepaid_fee) {
                let prepaid_coin = coin::extract(&mut fee_coin, prepaid_fee);
                coin::deposit<CoinType>(red_packets.config.admin, prepaid_coin);
            };
        } else {
            let prepaid_coin = coin::withdraw<AptosCoin>(operator, prepaid_fee);
            coin::deposit<AptosCoin>(red_packets.config.admin, prepaid_coin);
        };

        coin::deposit<CoinType>(red_packets.config.beneficiary, fee_coin);

        let escrow_coin = coin::withdraw<CoinType>(operator, escrow);
        info.remain_coin = coin::value(&escrow_coin);

        merge_coin<CoinType>(escrow_coin);

        bucket_table::add(&mut red_packets.store, id, info);

        event::emit_event<RedPacketEvent>(
            &mut red_packets.events,
            RedPacketEvent {
                id ,
                event_type: EVENT_TYPE_CREATE,
                remain_count: count,
                remain_balance: escrow
            },
        );

        red_packets.next_id = id + 1;
    }

    fun merge_coin<CoinType>(
        coin: Coin<CoinType>
    ) acquires Escrow {
        let escrow = borrow_global_mut<Escrow<CoinType>>(red_packet_address());
        coin::merge(&mut escrow.coin, coin);
    }

    #[test_only]
    public entry fun create2<CoinType>(
        operator: &signer,
        count: u64,
        total_balance: u64,
        total: u64
    ) acquires RedPackets, Escrow {
        let i = 0u64;

        while (i < total) {
            create<CoinType>(operator, count, total_balance);
            i = i + 1;
        }
    }

    // offchain check
    // 1. deduplicate lucky accounts
    // 2. check lucky account is exsist
    // 3. check total balance
    // call by comingchat
    public entry fun open<CoinType>(
        operator: &signer,
        id: u64,
        lucky_accounts: vector<address>,
        balances: vector<u64>
    ) acquires RedPackets, Escrow {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let accounts_len = vector::length(&lucky_accounts);
        let balances_len = vector::length(&balances);
        assert!(
            accounts_len == balances_len,
            error::invalid_argument(EACCOUNTS_BALANCES_LEN_MISMATCH),
        );

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());
        assert!(
            bucket_table::contains(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = bucket_table::borrow_mut(&mut red_packets.store, id);

        let escrow_coin = borrow_global_mut<Escrow<CoinType>>(red_packet_address());

        let total = 0u64;
        let i = 0u64;
        while (i < balances_len) {
            total = total + *vector::borrow(&balances, i);
            i = i + 1;
        };
        assert!(
            total <= info.remain_coin && total <= coin::value(&escrow_coin.coin),
            error::invalid_argument(EREDPACKET_INSUFFICIENT_BALANCES),
        );
        assert!(
            accounts_len <= info.remain_count,
            error::invalid_argument(EREDPACKET_TOO_MANY)
        );

        let i = 0u64;
        while (i < accounts_len) {
            let account = vector::borrow(&lucky_accounts, i);
            let balance = vector::borrow(&balances, i);
            coin::deposit(*account, coin::extract(&mut escrow_coin.coin, *balance));

            i = i + 1;
        };

        // update remain count
        info.remain_count = info.remain_count - accounts_len;
        // never overflow
        info.remain_coin = info.remain_coin - total;

        event::emit_event<RedPacketEvent>(
            &mut red_packets.events,
            RedPacketEvent {
                id ,
                event_type: EVENT_TYPE_OPEN,
                remain_count: info.remain_count,
                remain_balance: coin::value(&escrow_coin.coin)
            },
        );
    }

    // call by comingchat
    public entry fun close<CoinType>(
        operator: &signer,
        id: u64
    ) acquires RedPackets, Escrow {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());
        assert!(
            bucket_table::contains(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        drop<CoinType>(red_packets, id)
    }

    // call by comingchat
    // [start, end)
    // idempotent operation
    public entry fun batch_close<CoinType>(
        operator: &signer,
        start: u64,
        end: u64
    ) acquires RedPackets, Escrow {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());

        let id = start;
        while (id < end) {
            if (bucket_table::contains(& red_packets.store, &id)) {
                drop<CoinType>(red_packets, id);
            };
            id = id + 1;
        }
    }

    // drop the red packet
    fun drop<CoinType>(
        red_packets: &mut RedPackets,
        id: u64,
    ) acquires Escrow {
        let info = bucket_table::remove(&mut red_packets.store, &id);
        let escrow_coin = borrow_global_mut<Escrow<CoinType>>(red_packet_address());

        event::emit_event<RedPacketEvent>(
            &mut red_packets.events,
            RedPacketEvent {
                id ,
                event_type: EVENT_TYPE_CLOASE,
                remain_count: info.remain_count,
                remain_balance: info.remain_coin
            },
        );

        if (info.remain_coin > 0) {
            coin::deposit(
                red_packets.config.beneficiary,
                coin::extract(&mut escrow_coin.coin, info.remain_coin)
            );
        }
    }

    /// call by comingchat
    public entry fun set_admin(
        operator: &signer,
        admin: address
    ) acquires RedPackets {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let red_packets = borrow_global_mut<RedPackets>(operator_address);
        red_packets.config.admin = admin;

        event::emit_event<ConfigEvent>(
            &mut red_packets.config_events,
            ConfigEvent {
                active: red_packets.config
            },
        );
    }

    public entry fun set_fee_point(
        owner: &signer,
        new_fee_point: u8,
    ) acquires RedPackets {
        let operator_address = signer::address_of(owner);
        assert!(
            red_packet_address() == operator_address,
            error::invalid_argument(EREDPACKET_PERMISSION_DENIED),
        );
        let red_packets = borrow_global_mut<RedPackets>(operator_address);
        red_packets.config.fee_point = new_fee_point;

        event::emit_event<ConfigEvent>(
            &mut red_packets.config_events,
            ConfigEvent {
                active: red_packets.config
            },
        );
    }

    public entry fun set_base_prepaid_fee(
        operator: &signer,
        new_base_prepaid: u64,
    ) acquires RedPackets {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let red_packets = borrow_global_mut<RedPackets>(operator_address);
        red_packets.config.base_prepaid = new_base_prepaid;

        event::emit_event<ConfigEvent>(
            &mut red_packets.config_events,
            ConfigEvent {
                active: red_packets.config
            },
        );
    }

    public fun calculate_fee(
        balance: u64,
        fee_point: u8,
    ): (u64, u64) {
        let fee = balance / 10000 * (fee_point as u64);

        // never overflow
        (fee, balance - fee)
    }

    public fun info(
        id: u64
    ): (u64, u64) acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());
        assert!(
            bucket_table::contains(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = bucket_table::borrow(&mut red_packets.store, id);

        (info.remain_count, info.remain_coin)
    }

    public fun escrow_coins(
        id: u64
    ): u64 acquires RedPackets {
        let (_remain_count, escrow)  = info(id);
        escrow
    }

    public fun remain_count(
        id: u64
    ): u64 acquires RedPackets {
        let (remain_count, _escrow)  = info(id);
        remain_count
    }

    public fun current_id(): u64 acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        red_packets.next_id
    }

    public fun config(): Config acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        red_packets.config
    }

    public fun beneficiary(): address acquires RedPackets {
        config().beneficiary
    }

    public fun fee_point(): u8 acquires RedPackets {
        config().fee_point
    }

    public fun admin(): address acquires RedPackets {
        config().admin
    }

    public fun base_prepaid(): u64 acquires RedPackets {
        config().base_prepaid
    }
}
