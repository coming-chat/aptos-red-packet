/**
 *  Copyright 2022 ComingChat Authors.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */
module RedPacket::red_packet {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_std::type_info;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    const MAX_COUNT: u64 = 1000;

    const ENOT_ENOUGH_COIN: u64 = 1;
    const EREDPACKET_INFO_ADDRESS_MISMATCH: u64 = 2;
    const EREDPACKET_ALREADY_PUBLISHED: u64 = 3;
    const EACCOUNTS_BALANCES_LEN_MISMATCH: u64 = 4;
    const EREDPACKET_INSUFFICIENT_BALANCES: u64 = 5;
    const EREDPACKET_NOT_PUBLISHED: u64 = 6;
    const EREDPACKET_NOT_FOUND: u64 = 7;
    const EREDPACKET_TOO_MANY: u64 = 8;

    struct RedPacketInfo has store {
        coin: Coin<AptosCoin>,
        remain_count: u64,
    }

    struct RedPackets has key {
        next_id: u64,
        beneficiary: address,
        store: SimpleMap<u64, RedPacketInfo>,
    }

    public fun red_packet_address(): address {
        type_info::account_address(&type_info::type_of<RedPackets>())
    }

    public fun check_operator(operator_address: address, is_admin: bool) {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );
        assert!(
            !is_admin || red_packet_address() == operator_address,
            error::invalid_argument(EREDPACKET_INFO_ADDRESS_MISMATCH),
        );
    }

    // call by comingchat
    public entry fun initialze(
        owner: &signer,
        beneficiary: address
    ) {
        let owner_addr = signer::address_of(owner);
        assert!(
            red_packet_address() == owner_addr,
            error::invalid_argument(EREDPACKET_INFO_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_ALREADY_PUBLISHED),
        );

        let red_packets = RedPackets{
            next_id: 1,
            beneficiary,
            store: simple_map::create<u64, RedPacketInfo>()
        };

        move_to(owner, red_packets)
    }

    // call by anyone in comingchat
    public entry fun create(
        operator: &signer,
        count: u64,
        total_balance: u64
    ) acquires RedPackets {
        let operator_address = signer::address_of(operator);

        check_operator(operator_address, false);

        assert!(
            coin::balance<AptosCoin>(operator_address) >= total_balance,
            error::invalid_argument(ENOT_ENOUGH_COIN)
        );

        assert!(
            count <= MAX_COUNT,
            error::invalid_argument(EREDPACKET_TOO_MANY),
        );

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());

        let id = red_packets.next_id;

        let info  = RedPacketInfo {
            coin: coin::zero<AptosCoin>(),
            remain_count: count,
        };

        let coin = coin::withdraw<AptosCoin>(operator, total_balance);
        coin::merge(&mut info.coin, coin);

        simple_map::add(&mut red_packets.store, id, info);

        red_packets.next_id = id + 1;
    }

    // offchain check
    // 1. deduplicate lucky accounts
    // 2. check lucky account is exsist
    // call by comingchat
    public entry fun open(
        operator: &signer,
        id: u64,
        lucky_accounts: vector<address>,
        balances: vector<u64>
    ) acquires RedPackets {
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
            simple_map::contains_key(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = simple_map::borrow_mut(&mut red_packets.store, &id);

        let total = 0u64;
        let i = 0u64;
        while (i < balances_len) {
            total = total + *vector::borrow(&balances, i);
            i = i + 1;
        };
        assert!(
            total <= coin::value(&info.coin),
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
            coin::deposit(*account, coin::extract(&mut info.coin, *balance));

            i = i + 1;
        };

        // update remain count
        info.remain_count = info.remain_count - accounts_len;
    }

    // call by comingchat
    public entry fun close(
        operator: &signer,
        id: u64
    ) acquires RedPackets {
        let operator_address = signer::address_of(operator);
        check_operator(operator_address, true);

        let red_packets = borrow_global_mut<RedPackets>(red_packet_address());
        assert!(
            simple_map::contains_key(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = simple_map::borrow_mut(&mut red_packets.store, &id);

        coin::deposit(red_packets.beneficiary, coin::extract_all(&mut info.coin));
    }

    public fun escrow_aptos_coin(
        id: u64
    ): u64 acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        assert!(
            simple_map::contains_key(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = simple_map::borrow(&red_packets.store, &id);

        coin::value(&info.coin)
    }

    public fun remain_count(
        id: u64
    ): u64 acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        assert!(
            simple_map::contains_key(& red_packets.store, &id),
            error::not_found(EREDPACKET_NOT_FOUND),
        );

        let info = simple_map::borrow(&red_packets.store, &id);

        info.remain_count
    }

    public fun current_id(): u64 acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        red_packets.next_id
    }

    public fun beneficiary(): address acquires RedPackets {
        assert!(
            exists<RedPackets>(red_packet_address()),
            error::already_exists(EREDPACKET_NOT_PUBLISHED),
        );

        let red_packets = borrow_global<RedPackets>(red_packet_address());
        red_packets.beneficiary
    }
}
