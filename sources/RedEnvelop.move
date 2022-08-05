module RedEnvelop::red_envelop {
    use std::signer;
    use aptos_std::simple_map::{Self, SimpleMap, add};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin, CoinStore, merge};

    const ENOT_ENOUGH_COIN: u64 = 1;

    struct RedEnvelopInfo has store {
        coin: Coin<AptosCoin>,
        remain_count: u64,
        remain_balance: u64
    }

    struct RedEnvelops has key {
        next_id: u64,
        beneficiary: address,
        store: SimpleMap<u64, RedEnvelopInfo>,
    }

    public fun initialze(
        owner: &signer
    ) {
        let addr = signer::address_of(owner);
        if ( !exists<RedEnvelops>(addr) ) {
            let red_envelops = RedEnvelops{
                next_id: 1,
                beneficiary: addr,
                store: simple_map::create<u64, RedEnvelopInfo>()
            };
            move_to(owner, red_envelops)
        }
    }

    public entry fun create(
        creator: &signer,
        count: u64,
        total_balance: u64
    ) {
        let creator_address = signer::address_of(creator);
        assert!(coin::balance<AptosCoin>(creator_address) >= total_balance, ENOT_ENOUGH_COIN);

        let coin = coin::withdraw<AptosCoin>(creator, total_balance);
    }


    public entry fun open(
        id: u64,
        lucky_accounts: vector<address>,
        balances: vector<u64>
    ) {

    }

    public entry fun close(
        id: u64
    ) {

    }

}
