// Copyright 2022 ComingChat Authors. Licensed under Apache-2.0 License.
#[test_only]
module RedPacket::red_packet_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin::Self;

    use RedPacket::red_packet::{
        Self, initialize, create, open, close, set_admin, set_base_prepaid_fee,
        set_fee_point, batch_close, TestCoin, register_coin
    };

    #[test_only]
    fun setup_test_coin(
        minter: &signer,
        receiver: &signer,
        balance: u64
    ) {
        let minter_addr = signer::address_of(minter);
        let receiver_addr = signer::address_of(receiver);

        if (!coin::is_coin_initialized<TestCoin>()) {
            managed_coin::initialize<TestCoin>(
                minter,
                b"Test Coin",
                b"Test",
                8u8,
                true
            );
        };

        if (!coin::is_account_registered<TestCoin>(minter_addr)) {
            coin::register<TestCoin>(minter);
        };

        if (!coin::is_account_registered<TestCoin>(receiver_addr)) {
            coin::register<TestCoin>(receiver)
        };

        managed_coin::mint<TestCoin>(
            minter,
            receiver_addr,
            balance
        )
    }

    #[test_only]
    fun setup_aptos(
        aptos_framework: &signer,
        accounts: vector<address>,
        balances: vector<u64>
    ) {
        if (!coin::is_coin_initialized<AptosCoin>()) {
            let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
            coin::destroy_mint_cap<AptosCoin>(mint_cap);
            coin::destroy_burn_cap<AptosCoin>(burn_cap);
        };

        assert!(vector::length(&accounts) == vector::length(&balances), 1);

        while (!vector::is_empty(&accounts)) {
            let account = vector::pop_back(&mut accounts);
            let balance = vector::pop_back(&mut balances);
            aptos_account::create_account(account);
            aptos_coin::mint(aptos_framework, account, balance);
        };
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun initialize_should_work(
        aptos_framework: signer,
        operator: &signer,
        beneficiary: address
    ) {
        let operator_addr = signer::address_of(operator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary],
            vector<u64>[0, 0]
        );

        let operator_addr = signer::address_of(operator);
        initialize(operator, beneficiary, beneficiary);

        red_packet::check_operator(operator_addr, true);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    #[expected_failure(abort_code = 524289)]
    fun initialize_twice_should_fail(
        aptos_framework: signer,
        operator: &signer,
        beneficiary: address
    ) {
        let operator_addr = signer::address_of(operator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary],
            vector<u64>[0, 0]
        );

        initialize(operator, beneficiary, beneficiary);

        red_packet::check_operator(operator_addr, true);

        initialize(operator, beneficiary, beneficiary);
    }

    #[test(
        aptos_framework = @aptos_framework,
        beneficiary = @0x234,
        lucky = @0x345
    )]
    #[expected_failure(abort_code = 327683)]
    fun initialize_other_should_fail(
        aptos_framework: signer,
        lucky: &signer,
        beneficiary: address
    ) {
        let lucky_addr = signer::address_of(lucky);
        setup_aptos(
            &aptos_framework,
            vector<address>[lucky_addr, beneficiary],
            vector<u64>[0, 0]
        );

        initialize(lucky, beneficiary, beneficiary);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: address
    ) {
        let operator_addr = signer::address_of(&operator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary],
            vector<u64>[10000, 0]
        );

        initialize(&operator, beneficiary, beneficiary);

        register_coin<AptosCoin>(&operator);

        create<AptosCoin>(&operator, 0, 10, 10000);

        assert!(coin::balance<AptosCoin>(beneficiary) == 250, 0);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer
    ) {
        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary_addr],
            vector<u64>[1000, 0]
        );
        // creator, transfer TestCoin
        setup_test_coin(&operator, &operator, 10000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<TestCoin>(operator_addr) == 10000, 0);
        assert!(coin::balance<AptosCoin>(operator_addr) == 1000, 1);

        assert!(red_packet::base_prepaid(0) == 4, 2);

        // 1. pay some prepaid fee to admin: 4 * 10 = 40
        // 2. trasfer some TestCoin to contract: 10000
        create<TestCoin>(&operator, 0, 10, 10000);

        assert!(coin::balance<TestCoin>(beneficiary_addr) == 250, 3);
        assert!(coin::balance<AptosCoin>(operator_addr) == 960, 4);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun open_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: address,
        lucky1: address,
        lucky2: address,
    ) {
        let operator_addr = signer::address_of(&operator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary, lucky1, lucky2],
            vector<u64>[100000, 0, 0, 0]
        );

        initialize(&operator, beneficiary, beneficiary);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(operator_addr) == 100000, 0);

        create<AptosCoin>(&operator, 0, 2, 10000);

        assert!(red_packet::next_id(0) == 2, 1);
        assert!(red_packet::remain_count(0, 1) == 2, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(0, 1) == 10000 - 250, 3);
        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary) == 250, 4);

        assert!(coin::balance<AptosCoin>(operator_addr) == 90000, 5);

        open<AptosCoin>(
            &operator,
            0,
            1,
            vector<address>[lucky1, lucky2],
            vector<u64>[1000, 8750]
        );

        assert!(red_packet::remain_count(0, 1) == 0, 6);
        assert!(red_packet::escrow_coins(0, 1) == 0, 7);

        assert!(coin::balance<AptosCoin>(lucky1) == 1000, 8);
        assert!(coin::balance<AptosCoin>(lucky2) == 8750, 9);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun open_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary_addr, lucky1_addr, lucky2_addr],
            vector<u64>[1000, 0, 0, 0]
        );
        // creator, transfer TestCoin
        setup_test_coin(&operator, &operator, 100000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky1, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky2, 0);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<AptosCoin>(operator_addr) == 1000, 0);
        assert!(coin::balance<TestCoin>(operator_addr) == 100000, 1);

        create<TestCoin>(&operator, 0, 2, 10000);
        // prepaid fee: 2 * 4 = 8
        assert!(coin::balance<AptosCoin>(operator_addr) == 1000 - 2 * 4, 2);

        assert!(red_packet::next_id(0) == 2, 3);
        assert!(red_packet::remain_count(0, 1) == 2, 4);

        // 97.5%
        assert!(red_packet::escrow_coins(0, 1) == 10000 - 250, 5);
        // 2.5%
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 250, 6);

        assert!(coin::balance<TestCoin>(operator_addr) == 90000, 7);

        open<TestCoin>(
            &operator,
            0,
            1,
            vector<address>[lucky1_addr, lucky2_addr],
            vector<u64>[1000, 8750]
        );

        assert!(red_packet::remain_count(0, 1) == 0, 8);
        assert!(red_packet::escrow_coins(0, 1) == 0, 9);

        assert!(coin::balance<TestCoin>(lucky1_addr) == 1000, 10);
        assert!(coin::balance<TestCoin>(lucky2_addr) == 8750, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun close_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: address,
        lucky1: address,
        lucky2: address,
    ) {
        let operator_addr = signer::address_of(&operator);
        let creator_addr = signer::address_of(&creator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, creator_addr, beneficiary, lucky1, lucky2],
            vector<u64>[0, 100000, 0, 0, 0]
        );

        initialize(&operator, beneficiary, beneficiary);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(creator_addr) == 100000, 0);

        create<AptosCoin>(&creator, 0, 3, 30000);

        assert!(red_packet::next_id(0) == 2, 1);
        assert!(red_packet::remain_count(0, 1) == 3, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(0, 1) == 30000 - 750 , 3);
        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary) == 750, 4);

        assert!(coin::balance<AptosCoin>(creator_addr) == 70000, 5);

        open<AptosCoin>(
            &operator,
            0,
            1,
            vector<address>[lucky1, lucky2],
            vector<u64>[1000, 9000]
        );

        assert!(red_packet::remain_count(0, 1) == 1, 7);
        assert!(red_packet::escrow_coins(0, 1) == 19250, 8);

        close<AptosCoin>(&operator, 0, 1);

        assert!(coin::balance<AptosCoin>(lucky1) == 1000, 9);
        assert!(coin::balance<AptosCoin>(lucky2) == 9000, 10);
        assert!(coin::balance<AptosCoin>(beneficiary) == 750 + 19250, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun close_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        let operator_addr = signer::address_of(&operator);
        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, creator_addr, beneficiary_addr, lucky1_addr, lucky2_addr],
            vector<u64>[0, 1000, 0, 0, 0]
        );
        // creator, transfer TestCoin
        setup_test_coin(&operator, &creator, 100000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky1, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky2, 0);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<TestCoin>(creator_addr) == 100000, 0);
        assert!(coin::balance<AptosCoin>(creator_addr) == 1000, 1);

        create<TestCoin>(&creator, 0, 3, 30000);

        assert!(coin::balance<AptosCoin>(creator_addr) == 1000 - 3 * 4, 1);

        assert!(red_packet::next_id(0) == 2, 1);
        assert!(red_packet::remain_count(0, 1) == 3, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(0, 1) == 30000 - 750 , 3);
        // 2.5%
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 750, 4);

        assert!(coin::balance<TestCoin>(creator_addr) == 70000, 5);

        open<TestCoin>(
            &operator,
            0,
            1,
            vector<address>[lucky1_addr, lucky2_addr],
            vector<u64>[1000, 9000]
        );

        assert!(red_packet::remain_count(0, 1) == 1, 7);
        assert!(red_packet::escrow_coins(0, 1) == 19250, 8);

        close<TestCoin>(&operator, 0, 1);

        assert!(coin::balance<TestCoin>(lucky1_addr) == 1000, 9);
        assert!(coin::balance<TestCoin>(lucky2_addr) == 9000, 10);
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 750 + 19250, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun batch_close_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: address,
        lucky1: address,
        lucky2: address,
    ) {
        let operator_addr = signer::address_of(&operator);
        let creator_addr = signer::address_of(&creator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, creator_addr, beneficiary, lucky1, lucky2],
            vector<u64>[0, 100000, 0, 0, 0]
        );

        initialize(&operator, beneficiary, beneficiary);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(creator_addr) == 100000, 0);
        assert!(red_packet::next_id(0) == 1, 1);

        create<AptosCoin>(&creator, 0, 3, 30000);
        create<AptosCoin>(&creator, 0, 3, 30000);
        create<AptosCoin>(&creator, 0, 3, 30000);

        assert!(red_packet::next_id(0) == 4, 2);
        assert!(red_packet::remain_count(0, 1) == 3, 3);
        assert!(red_packet::remain_count(0, 2) == 3, 4);
        assert!(red_packet::remain_count(0, 3) == 3, 5);

        // 97.5%
        assert!(red_packet::escrow_coins(0, 1) == 30000 - 750 , 6);
        assert!(red_packet::escrow_coins(0, 2) == 30000 - 750 , 7);
        assert!(red_packet::escrow_coins(0, 3) == 30000 - 750 , 8);

        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary) == 750 * 3, 9);

        assert!(coin::balance<AptosCoin>(creator_addr) == 10000, 10);

        open<AptosCoin>(
            &operator,
            0,
            1,
            vector<address>[lucky1, lucky2],
            vector<u64>[1000, 9000]
        );

        assert!(red_packet::remain_count(0, 1) == 1, 11);
        assert!(red_packet::escrow_coins(0, 1) == 19250, 12);

        batch_close<AptosCoin>(&operator, 0, 1, 4);
        // batch close again
        batch_close<AptosCoin>(&operator, 0, 1, 4);

        assert!(coin::balance<AptosCoin>(lucky1) == 1000, 13);
        assert!(coin::balance<AptosCoin>(lucky2) == 9000, 14);
        assert!(coin::balance<AptosCoin>(beneficiary) == 750 + 19250 + 60000, 15);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
        new_admin = @0x456,
    )]
    fun set_admin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: address,
        admin: signer,
        new_admin: signer,
    ) {
        let operator_addr = signer::address_of(&operator);
        let admin_addr = signer::address_of(&admin);
        let new_admin_addr = signer::address_of(&new_admin);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary, admin_addr, new_admin_addr],
            vector<u64>[0, 0, 10000, 100]
        );

        initialize(&operator, beneficiary, admin_addr);

        register_coin<AptosCoin>(&operator);

        red_packet::check_operator(operator_addr, true);

        assert!(red_packet::admin() == admin_addr, 0);
        set_admin(&operator, new_admin_addr);
        assert!(red_packet::admin() == new_admin_addr, 1);

        assert!(red_packet::base_prepaid(0) == 4, 2);

        create<AptosCoin>(&admin, 0, 1, 10000);

        // 97.5%

        assert!(red_packet::escrow_coins(0, 1) == 10000 - 250, 3);

        // 2.5%

        assert!(coin::balance<AptosCoin>(beneficiary) == 250 - 4, 4);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 5);

        open<AptosCoin>(
            &new_admin,
            0,
            1,
            vector<address>[admin_addr],
            vector<u64>[10000 - 250 - 100]
        );
        assert!(coin::balance<AptosCoin>(admin_addr) == 10000 - 250 - 100, 6);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 7);

        close<AptosCoin>(&new_admin, 0, 1);
        assert!(coin::balance<AptosCoin>(beneficiary) == 250 - 4 + 100, 8);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
    )]
    fun set_point_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: address,
        admin: address,
    ) {
        let operator_addr = signer::address_of(&operator);
        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary, admin],
            vector<u64>[0, 0, 0]
        );

        initialize(&operator, beneficiary, admin);

        register_coin<AptosCoin>(&operator);

        red_packet::check_operator(operator_addr, true);

        // 2.5%
        assert!(red_packet::fee_point(0) == 250, 0);

        set_fee_point(&operator, 0, 100);

        // 1%
        assert!(red_packet::fee_point(0) == 100, 1);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
    )]
    fun set_base_prepaid_fee_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: address,
        admin: address,
    ) {
        let operator_addr = signer::address_of(&operator);

        setup_aptos(
            &aptos_framework,
            vector<address>[operator_addr, beneficiary, admin],
            vector<u64>[0, 0, 0]
        );

        initialize(&operator, beneficiary, admin);

        register_coin<AptosCoin>(&operator);

        red_packet::check_operator(operator_addr, true);

        // 4
        assert!(red_packet::base_prepaid(0) == 4, 0);

        set_base_prepaid_fee(&operator, 0, 40);

        // 40
        assert!(red_packet::base_prepaid(0) == 40, 1);
    }
}
