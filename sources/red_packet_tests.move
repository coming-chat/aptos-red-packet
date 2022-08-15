#[test_only]
module std::red_packet_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;

    use RedPacket::red_packet::{
        Self, initialze, check_operator, create, open, close
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

        initialze(operator, beneficiary);

        check_operator(operator_addr, true);
    }

    #[test(operator = @0x123, beneficiary = @0x234)]
    #[expected_failure]
    fun initialize_twice_should_fail(operator: &signer, beneficiary: address) {
        let operator_addr = signer::address_of(operator);

        initialze(operator, beneficiary);

        check_operator(operator_addr, true);

        initialze(operator, beneficiary);
    }

    #[test(beneficiary = @0x234, lucky = @0x345)]
    #[expected_failure]
    fun initialize_other_should_fail(lucky: &signer, beneficiary: address) {
        initialze(lucky, beneficiary);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_should_work(
        core_resources: signer,
        aptos_framework: signer,
        operator: signer,
        beneficiary: address
    ) {
        let (mint_cap, burn_cap) = aptos_coin::initialize(&aptos_framework, &core_resources);
        setup_aptos(&aptos_framework, &operator, 100);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        initialze(&operator, beneficiary);

        create(&operator, 10, 100);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 =@0x999,
    )]
    fun open_should_work(
        core_resources: signer,
        aptos_framework: signer,
        operator: signer,
        beneficiary: address,
        lucky1: signer,
        lucky2: signer,
    ) {
        let (mint_cap, burn_cap) = aptos_coin::initialize(&aptos_framework, &core_resources);
        setup_aptos(&aptos_framework, &operator, 100);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let operator_addr = signer::address_of(&operator);

        initialze(&operator, beneficiary);

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
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator  = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 =@0x999,
    )]
    fun close_should_work(
        core_resources: signer,
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        let (mint_cap, burn_cap) = aptos_coin::initialize(&aptos_framework, &core_resources);
        setup_aptos(&aptos_framework, &creator, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialze(&operator, beneficiary_addr);

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
}
