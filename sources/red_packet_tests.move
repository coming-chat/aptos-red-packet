#[test_only]
module std::red_packet_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;

    use RedPacket::red_packet::{
        Self, admin, initialze, check_operator, create, open, close,
        set_admin, base_prepaid, set_base_prepaid_fee, set_fee_point,
        fee_point, escrow_aptos_coin
    };

    #[test_only]
    fun setup_aptos(
        aptos_framework: &signer,
        account: &signer,
        balance: u64
    ) {
        let account_addr = signer::address_of(account);

        coin::register_for_test<AptosCoin>(account);
        aptos_coin::mint(aptos_framework, account_addr, balance);
    }

    #[test(operator = @0x123, beneficiary = @0x234)]
    fun initialize_should_work(operator: &signer, beneficiary: address) {
        let operator_addr = signer::address_of(operator);

        initialze(operator, beneficiary, beneficiary);

        check_operator(operator_addr, true);
    }

    #[test(operator = @0x123, beneficiary = @0x234)]
    #[expected_failure(abort_code = 524291)]
    fun initialize_twice_should_fail(operator: &signer, beneficiary: address) {
        let operator_addr = signer::address_of(operator);

        initialze(operator, beneficiary, beneficiary);

        check_operator(operator_addr, true);

        initialze(operator, beneficiary, beneficiary);
    }

    #[test(beneficiary = @0x234, lucky = @0x345)]
    #[expected_failure(abort_code = 65538)]
    fun initialize_other_should_fail(lucky: &signer, beneficiary: address) {
        initialze(lucky, beneficiary, beneficiary);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &operator, 10000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let beneficiary_addr = signer::address_of(&beneficiary);

        initialze(&operator, beneficiary_addr, beneficiary_addr);

        create(&operator, 10, 10000);

        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250, 0);
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
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &operator, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialze(&operator, beneficiary_addr, beneficiary_addr);

        assert!(coin::balance<AptosCoin>(operator_addr) == 100, 0);

        create(&operator, 2, 10);

        assert!(red_packet::current_id() == 2, 1);
        assert!(red_packet::remain_count(1) == 2, 2);
        assert!(red_packet::escrow_aptos_coin(1) == 10, 3);
        assert!(coin::balance<AptosCoin>(operator_addr) == 90, 4);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1);
        vector::push_back(&mut balances, 9);

        open(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 0, 5);
        assert!(red_packet::escrow_aptos_coin(1) == 0, 6);

        assert!(coin::balance<AptosCoin>(lucky1_addr) == 1, 7);
        assert!(coin::balance<AptosCoin>(lucky2_addr) == 9, 8);
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
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &creator, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialze(&operator, beneficiary_addr, beneficiary_addr);

        assert!(coin::balance<AptosCoin>(creator_addr) == 100, 0);

        create(&creator, 3, 30);

        assert!(red_packet::current_id() == 2, 1);
        assert!(red_packet::remain_count(1) == 3, 2);
        assert!(red_packet::escrow_aptos_coin(1) == 30, 3);
        assert!(coin::balance<AptosCoin>(creator_addr) == 70, 4);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 0, 5);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1);
        vector::push_back(&mut balances, 9);

        open(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 1, 6);
        assert!(red_packet::escrow_aptos_coin(1) == 20, 7);

        close(&operator, 1);

        assert!(coin::balance<AptosCoin>(lucky1_addr) == 1, 8);
        assert!(coin::balance<AptosCoin>(lucky2_addr) == 9, 9);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 20, 10);
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
        beneficiary: signer,
        admin: signer,
        new_admin: signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &admin, 10000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &new_admin, 100);

        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);
        let new_admin_addr = signer::address_of(&new_admin);

        initialze(&operator, beneficiary_addr, admin_addr);
        check_operator(operator_addr, true);

        assert!(admin() == admin_addr, 0);
        set_admin(&operator, new_admin_addr);
        assert!(admin() == new_admin_addr, 1);

        assert!(base_prepaid() == 4, 2);

        create(&admin, 1, 10000);

        // 97.5%

        assert!(escrow_aptos_coin(1) == 10000 - 250, 3);

        // 2.5%

        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250 - 4, 4);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 5);

        let accounts = vector::empty<address>();
        vector::push_back(&mut accounts, admin_addr);
        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 10000 - 250 - 100);

        open(&new_admin, 1, accounts, balances);
        assert!(coin::balance<AptosCoin>(admin_addr) == 10000 - 250 - 100, 6);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 7);

        close(&new_admin, 1);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250 - 4 + 100, 8);
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
        beneficiary: signer,
        admin: signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &admin, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);

        initialze(&operator, beneficiary_addr, admin_addr);
        check_operator(operator_addr, true);

        // 2.5%
        assert!(fee_point() == 250, 0);

        set_fee_point(&operator, 100);

        // 1%
        assert!(fee_point() == 100, 1);
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
        beneficiary: signer,
        admin: signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        setup_aptos(&aptos_framework, &admin, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);

        initialze(&operator, beneficiary_addr, admin_addr);
        check_operator(operator_addr, true);

        // 4
        assert!(base_prepaid() == 4, 0);

        set_base_prepaid_fee(&operator, 40);

        // 40
        assert!(base_prepaid() == 40, 1);
    }
}
