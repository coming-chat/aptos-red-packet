// Copyright 2022 ComingChat Authors. Licensed under Apache-2.0 License.
module RedPacket::red_packet {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string::{Self, String};
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

    const EREDPACKET_HAS_PUBLISHED: u64 = 1;
    const EREDPACKET_NOT_PUBLISHED: u64 = 2;
    const EREDPACKET_PERMISSION_DENIED: u64 = 3;
    const EREDPACKET_ACCOUNTS_BALANCES_MISMATCH: u64 = 4;
    const EREDPACKET_INSUFFICIENT_BALANCES: u64 = 5;
    const EREDPACKET_NOT_FOUND: u64 = 6;
    const EREDPACKET_ACCOUNT_TOO_MANY: u64 = 7;
    const EREDPACKET_BALANCE_TOO_LITTLE: u64 = 8;
    const EREDPACKET_HAS_REGISTERED: u64 = 9;
    const EREDPACKET_COIN_TYPE_MISMATCH: u64 = 10;

    const EVENT_TYPE_CREATE: u8 = 0;
    const EVENT_TYPE_OPEN: u8 = 1;
    const EVENT_TYPE_CLOASE: u8 = 2;

    /// Event emitted when created/opened/closed a red packet.
    struct RedPacketEvent has drop, store {
        id: u64,
        handler_index: u64,
        event_type: u8,
        remain_count: u64,
        remain_balance: u64
    }

    struct ConfigEvent has drop, store {
        handler_index: u64,
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
        fee_point: u8,
        base_prepaid: u64,
    }

    struct RedPacketHandler has store {
        next_id: u64,
        config: Config,
        coin_type: String,
        handler_index: u64,
        escrow_address: address,
        store: bucket_table::BucketTable<u64, RedPacketInfo>,
    }

    struct GlobalConfig has key {
        beneficiary: address,
        admin: address,
        handlers: vector<RedPacketHandler>,
        events: EventHandle<RedPacketEvent>,
        config_events: EventHandle<ConfigEvent>
    }

    struct Escrow<phantom CoinType> has key {
        coin: Coin<CoinType>,
    }

    /// A helper function that returns the address of CoinType.
    public fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    public fun check_operator(
        operator_address: address,
        require_admin: bool
    ) acquires GlobalConfig {
        assert!(
            exists<GlobalConfig>(@RedPacket),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );
        assert!(
            !require_admin || admin() == operator_address || @RedPacket == operator_address,
            error::permission_denied(EREDPACKET_PERMISSION_DENIED),
        );
    }

    /// call by comingchat owner
    /// set beneficiary and admin
    public entry fun initialize(
        owner: &signer,
        beneficiary: address,
        admin: address,
    ) {
        let owner_addr = signer::address_of(owner);
        assert!(
            @RedPacket == owner_addr,
            error::permission_denied(EREDPACKET_PERMISSION_DENIED),
        );

        assert!(
            !exists<GlobalConfig>(@RedPacket),
            error::already_exists(EREDPACKET_HAS_PUBLISHED),
        );

        move_to(
            owner,
            GlobalConfig {
                beneficiary,
                admin,
                handlers: vector::empty<RedPacketHandler>(),
                events: account::new_event_handle<RedPacketEvent>(owner),
                config_events: account::new_event_handle<ConfigEvent>(owner)
            }
        );
    }

    /// call by admin in comingchat
    /// register a coin type for red packet and initialize it
    public entry fun register_coin<CoinType>(
        admin: &signer
    ) acquires GlobalConfig {
        let admin_addr = signer::address_of(admin);
        check_operator(admin_addr, true);

        let coin_type = type_info::type_name<CoinType>();

        let (resource, _signer_cap) = account::create_resource_account(admin, *string::bytes(&coin_type));

        assert!(
            !exists<Escrow<CoinType>>(signer::address_of(&resource)),
            EREDPACKET_HAS_REGISTERED
        );
        move_to(
            &resource,
            Escrow<CoinType> {
                coin: coin::zero<CoinType>()
            }
        );

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let next_handler_index = vector::length(&global.handlers);
        let new_red_packet = RedPacketHandler {
            next_id: 1,
            config: Config {
                fee_point: INIT_FEE_POINT,
                base_prepaid: BASE_PREPAID_FEE,
            },
            coin_type,
            handler_index: next_handler_index,
            escrow_address: signer::address_of(&resource),
            store: bucket_table::new<u64, RedPacketInfo>(1),
        };

        vector::push_back(&mut global.handlers, new_red_packet)
    }

    /// call by anyone in comingchat
    /// create a red packet
    public entry fun create<CoinType>(
        operator: &signer,
        handler_index: u64,
        count: u64,
        total_balance: u64
    ) acquires GlobalConfig, Escrow {
        // 1. check args

        assert!(
            total_balance >= MIN_BALANCE,
            error::invalid_argument(EREDPACKET_BALANCE_TOO_LITTLE)
        );
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, false);
        assert!(
            coin::balance<CoinType>(operator_address) >= total_balance,
            error::invalid_argument(EREDPACKET_INSUFFICIENT_BALANCES)
        );
        assert!(
            count <= MAX_COUNT,
            error::invalid_argument(EREDPACKET_ACCOUNT_TOO_MANY),
        );

        // 2. get handler

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);
        assert!(
            handler.coin_type == type_info::type_name<CoinType>(),
            error::invalid_argument(EREDPACKET_COIN_TYPE_MISMATCH)
        );

        let id = handler.next_id;
        let info  = RedPacketInfo {
            remain_coin: 0,
            remain_count: count,
        };

        // 3. handle assets

        let prepaid_fee = count * handler.config.base_prepaid;
        let (fee,  escrow) = calculate_fee(total_balance, handler.config.fee_point);
        let fee_coin = coin::withdraw<CoinType>(operator, fee);
        if (coin_address<CoinType>() == @aptos_std && coin::symbol<CoinType>() == string::utf8(b"APT")) {
            if (fee > prepaid_fee) {
                let prepaid_coin = coin::extract(&mut fee_coin, prepaid_fee);
                coin::deposit<CoinType>(global.admin, prepaid_coin);
            };
        } else {
            let prepaid_coin = coin::withdraw<AptosCoin>(operator, prepaid_fee);
            coin::deposit<AptosCoin>(global.admin, prepaid_coin);
        };

        coin::deposit<CoinType>(global.beneficiary, fee_coin);

        let escrow_coin = coin::withdraw<CoinType>(operator, escrow);
        info.remain_coin = coin::value(&escrow_coin);
        merge_coin<CoinType>(handler.escrow_address, escrow_coin);

        // 4. store info

        bucket_table::add(&mut handler.store, id, info);

        // 5. update next_id

        handler.next_id = id + 1;

        // 6. emit create event

        event::emit_event<RedPacketEvent>(
            &mut global.events,
            RedPacketEvent {
                id,
                handler_index: handler.handler_index,
                event_type: EVENT_TYPE_CREATE,
                remain_count: count,
                remain_balance: escrow
            },
        );
    }

    fun merge_coin<CoinType>(
        resource: address,
        coin: Coin<CoinType>
    ) acquires Escrow {
        let escrow = borrow_global_mut<Escrow<CoinType>>(resource);
        coin::merge(&mut escrow.coin, coin);
    }

    /// offchain check
    /// 1. deduplicate lucky accounts
    /// 2. check lucky account is exsist
    /// 3. check total balance
    /// call by comingchat admin
    public entry fun open<CoinType>(
        operator: &signer,
        handler_index: u64,
        id: u64,
        lucky_accounts: vector<address>,
        balances: vector<u64>
    ) acquires GlobalConfig, Escrow {
        // 1. check args

        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let accounts_len = vector::length(&lucky_accounts);
        let balances_len = vector::length(&balances);
        assert!(
            accounts_len == balances_len,
            error::invalid_argument(EREDPACKET_ACCOUNTS_BALANCES_MISMATCH),
        );

        // 2. get handler

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);
        assert!(
            bucket_table::contains(&handler.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );
        assert!(
            handler.coin_type == type_info::type_name<CoinType>(),
            error::invalid_argument(EREDPACKET_COIN_TYPE_MISMATCH)
        );

        // 3. check red packet stats

        let info = bucket_table::borrow_mut(&mut handler.store, id);
        let escrow_coin = borrow_global_mut<Escrow<CoinType>>(handler.escrow_address);

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
            error::invalid_argument(EREDPACKET_ACCOUNT_TOO_MANY)
        );

        // 4. handle assets

        let i = 0u64;
        while (i < accounts_len) {
            let account = vector::borrow(&lucky_accounts, i);
            let balance = vector::borrow(&balances, i);
            coin::deposit(*account, coin::extract(&mut escrow_coin.coin, *balance));

            i = i + 1;
        };

        // 5. update red packet stats

        // update remain count
        info.remain_count = info.remain_count - accounts_len;
        // never overflow
        info.remain_coin = info.remain_coin - total;

        // 6. emit open event

        event::emit_event<RedPacketEvent>(
            &mut global.events,
            RedPacketEvent {
                id ,
                handler_index: handler.handler_index,
                event_type: EVENT_TYPE_OPEN,
                remain_count: info.remain_count,
                remain_balance: coin::value(&escrow_coin.coin)
            },
        );
    }

    /// call by comingchat admin
    /// close a red packet
    public entry fun close<CoinType>(
        operator: &signer,
        handler_index: u64,
        id: u64
    ) acquires GlobalConfig, Escrow {
        // 1. check args

        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        // 2. get handler

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);
        assert!(
            bucket_table::contains(&handler.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );
        assert!(
            handler.coin_type == type_info::type_name<CoinType>(),
            error::invalid_argument(EREDPACKET_COIN_TYPE_MISMATCH)
        );

        // 3. drop the red packet
        drop<CoinType>(handler, &mut global.events, global.beneficiary, id);
    }

    /// call by comingchat admin
    /// [start, end)
    /// idempotent operation
    public entry fun batch_close<CoinType>(
        operator: &signer,
        handler_index: u64,
        start: u64,
        end: u64
    ) acquires GlobalConfig, Escrow {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);
        assert!(
            handler.coin_type == type_info::type_name<CoinType>(),
            error::invalid_argument(EREDPACKET_COIN_TYPE_MISMATCH)
        );

        let id = start;
        while (id < end) {
            if (bucket_table::contains(&handler.store, &id)) {
                drop<CoinType>(handler, &mut global.events, global.beneficiary, id);
            };
            id = id + 1;
        }
    }

    /// drop the red packet
    fun drop<CoinType>(
        handler: &mut RedPacketHandler,
        event_handler: &mut EventHandle<RedPacketEvent>,
        beneficiary_addr: address,
        id: u64,
    ) acquires Escrow {
        // 1. handle remain assets

        let info = bucket_table::remove(&mut handler.store, &id);
        let escrow_coin = borrow_global_mut<Escrow<CoinType>>(handler.escrow_address);

        if (info.remain_coin > 0) {
            coin::deposit(
                beneficiary_addr,
                coin::extract(&mut escrow_coin.coin, info.remain_coin)
            );
        };

        // 2. emit close event

        event::emit_event<RedPacketEvent>(
            event_handler,
            RedPacketEvent {
                id ,
                handler_index: handler.handler_index,
                event_type: EVENT_TYPE_CLOASE,
                remain_count: info.remain_count,
                remain_balance: info.remain_coin
            },
        );
    }

    /// call by comingchat owner
    /// set new admin
    public entry fun set_admin(
        operator: &signer,
        admin: address
    ) acquires GlobalConfig {
        let operator_address = signer::address_of(operator);
        assert!(
            @RedPacket == operator_address,
            error::invalid_argument(EREDPACKET_PERMISSION_DENIED),
        );

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        global.admin = admin;
    }

    /// call by comingchat owner
    /// set new fee point
    public entry fun set_fee_point(
        owner: &signer,
        handler_index: u64,
        new_fee_point: u8,
    ) acquires GlobalConfig {
        let operator_address = signer::address_of(owner);
        assert!(
            @RedPacket == operator_address,
            error::invalid_argument(EREDPACKET_PERMISSION_DENIED),
        );

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);

        handler.config.fee_point = new_fee_point;

        event::emit_event<ConfigEvent>(
            &mut global.config_events,
            ConfigEvent {
                handler_index: handler.handler_index,
                active: handler.config
            },
        );
    }

    /// call by comingchat admin
    /// set new base prepaid fee
    public entry fun set_base_prepaid_fee(
        operator: &signer,
        handler_index: u64,
        new_base_prepaid: u64,
    ) acquires GlobalConfig {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);

        handler.config.base_prepaid = new_base_prepaid;

        event::emit_event<ConfigEvent>(
            &mut global.config_events,
            ConfigEvent {
                handler_index: handler.handler_index,
                active: handler.config
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
        handler_index: u64,
        id: u64
    ): (u64, u64) acquires GlobalConfig {
        assert!(
            exists<GlobalConfig>(@RedPacket),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let global = borrow_global_mut<GlobalConfig>(@RedPacket);
        let handler = vector::borrow_mut(&mut global.handlers, handler_index);

        assert!(
            bucket_table::contains(&handler.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = bucket_table::borrow(&mut handler.store, id);

        (info.remain_count, info.remain_coin)
    }

    public fun escrow_coins(
        handler_index: u64,
        id: u64
    ): u64 acquires GlobalConfig {
        let (_remain_count, escrow)  = info(handler_index, id);
        escrow
    }

    public fun remain_count(
        handler_index: u64,
        id: u64
    ): u64 acquires GlobalConfig {
        let (remain_count, _escrow)  = info(handler_index, id);
        remain_count
    }

    public fun beneficiary(): address acquires GlobalConfig {
        borrow_global<GlobalConfig>(@RedPacket).beneficiary
    }

    public fun admin(): address acquires GlobalConfig {
        borrow_global<GlobalConfig>(@RedPacket).admin
    }

    public fun fee_point(handler_index: u64): u8 acquires GlobalConfig {
        let global = borrow_global<GlobalConfig>(@RedPacket);
        vector::borrow(&global.handlers, handler_index).config.fee_point
    }

    public fun base_prepaid(handler_index: u64): u64 acquires GlobalConfig {
        let global = borrow_global<GlobalConfig>(@RedPacket);
        vector::borrow(&global.handlers, handler_index).config.base_prepaid
    }

    public fun next_id(handler_index: u64): u64 acquires GlobalConfig {
        let global = borrow_global<GlobalConfig>(@RedPacket);
        vector::borrow(&global.handlers, handler_index).next_id
    }

    public fun coin_type(index: u64): String acquires GlobalConfig {
        let global = borrow_global<GlobalConfig>(@RedPacket);
        vector::borrow(&global.handlers, index).coin_type
    }

    #[test_only]
    struct TestCoin {}

    #[test_only]
    public entry fun create2<CoinType>(
        operator: &signer,
        handler_index: u64,
        count: u64,
        total_balance: u64,
        total: u64
    ) acquires GlobalConfig, Escrow {
        let i = 0u64;

        while (i < total) {
            create<CoinType>(operator, handler_index, count, total_balance);
            i = i + 1;
        }
    }
}
