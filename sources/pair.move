module skyx_amm::pair {
    use std::string::{ utf8, String };
    use std::u128::{ min, sqrt };
    use sui::object::{ new as new_object };
    use sui::coin::{ Coin, from_balance, zero };
    use sui::balance::{ Supply, create_supply };
    use sui::transfer::public_transfer;
    use sui::event::emit;
    use skyx_amm::type_helper::get_type_name;
    use skyx_amm::treasury::{ Treasury, treasurer };

    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 400;
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 401;
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 402;
    const ERR_K: u64 = 403;
    const ERR_INSUFFICIENT_LIQUIDITY_MINT: u64 = 404;
    const ERR_TOO_LARGE_FEE_RATE: u64 = 405;

    const MAXIMUM_FEE_RATE: u64 = 10000;
    const MINIMUM_LIQUIDITY: u64 = 1000;

    public struct LP<phantom T0, phantom T1> has drop {
        dummy_field: bool,
    }
    
    #[allow(lint(coin_field))]
    public struct PairMetadata<phantom T0, phantom T1> has store, key {
        id: UID,
        reserve_x: Coin<T0>,
        reserve_y: Coin<T1>,
        k_last: u128,
        lp_supply: Supply<LP<T0, T1>>,
        creator_liquidity: u64, // only for tracking data
        acc_x_fee_for_creator: u64, // only for tracking data
        acc_y_fee_for_creator: u64, // only for tracking data
        fee_rate: u64,
    }
    
    public struct LiquidityAdded has copy, drop {
        user: address,
        pair: address, 
        coin_x: String,
        coin_y: String,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee: u64,
    }
    
    public struct LiquidityRemoved has copy, drop {
        user: address,
        pair: address,
        coin_x: String,
        coin_y: String,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee: u64,
    }
    
    public struct Swapped has copy, drop {
        user: address,
        pair: address,
        coin_x: String,
        coin_y: String,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64,
    }
    
    public struct FeeForCreatorAdded has copy, drop {
        pair: address,
        coin_x: String,
        coin_y: String,
        added_x_fee_for_creator: u64,
        added_y_fee_for_creator: u64,
    }

    fun accumulate_fees_for_creator<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        amount_x_in: u64,
        amount_y_in: u64
    ) {
        let x_fee = amount_x_in * pair.fee_rate / 10000;
        let y_fee = amount_y_in * pair.fee_rate / 10000;
        let total_supply = total_lp_supply<T0, T1>(pair) as u128;
        let added_x_fee_for_creator = (((x_fee as u128) * (pair.creator_liquidity as u128)) / total_supply) as u64;
        let added_y_fee_for_creator = (((y_fee as u128) * (pair.creator_liquidity as u128)) / total_supply) as u64;
        pair.acc_x_fee_for_creator = pair.acc_x_fee_for_creator + added_x_fee_for_creator;
        pair.acc_y_fee_for_creator = pair.acc_y_fee_for_creator + added_y_fee_for_creator;

        let add_fee_for_creator_event = FeeForCreatorAdded{
            pair: pair.pair_id(),
            coin_x: get_type_name<T0>(),
            coin_y: get_type_name<T1>(),
            added_x_fee_for_creator: added_x_fee_for_creator,
            added_y_fee_for_creator: added_y_fee_for_creator,
        };
        emit<FeeForCreatorAdded>(add_fee_for_creator_event)
    }
    
    public fun swap<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        coin_x_in: Coin<T0>,
        amount_x_out: u64,
        coin_y_in: Coin<T1>,
        amount_y_out: u64,
        ctx: &mut TxContext
    ) : (Coin<T0>, Coin<T1>) {
        assert!(amount_x_out > 0 || amount_y_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        assert!(amount_x_out < reserve_x && amount_y_out < reserve_y, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_x_in = coin_x_in.value();
        let amount_y_in = coin_y_in.value();
        assert!(amount_x_in > 0 || amount_y_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        deposit_x<T0, T1>(pair, coin_x_in);
        deposit_y<T0, T1>(pair, coin_y_in);
        let (new_reserve_x, new_reserve_y) = get_reserves<T0, T1>(pair);
        assert!(((new_reserve_x as u256) * (10000 as u256) - (amount_x_in as u256) * (pair.fee_rate as u256)) * ((new_reserve_y as u256) * (10000 as u256) - (amount_y_in as u256) * (pair.fee_rate as u256)) >= (reserve_x as u256) * (reserve_y as u256) * (10000 as u256) * (10000 as u256), ERR_K);

        // only for tracking data
        accumulate_fees_for_creator(pair, amount_x_in, amount_y_in);
        
        let swap_event = Swapped{
            user         : ctx.sender(), 
            pair         : pair.pair_id(),
            coin_x       : get_type_name<T0>(), 
            coin_y       : get_type_name<T1>(), 
            amount_x_in  : amount_x_in, 
            amount_y_in  : amount_y_in, 
            amount_x_out : amount_x_out, 
            amount_y_out : amount_y_out,
        };
        emit<Swapped>(swap_event);
        (extract_x<T0, T1>(pair, amount_x_out, ctx), extract_y<T0, T1>(pair, amount_y_out, ctx))
    }
    
    public fun burn<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        treasury: &Treasury,
        lp_token: Coin<LP<T0, T1>>,
        ctx: &mut TxContext
    ) : (Coin<T0>, Coin<T1>) {
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let liquidity = lp_token.value();
        let total_supply = total_lp_supply<T0, T1>(pair) as u128;
        let amount_x = ((liquidity as u128) * (reserve_x as u128) / total_supply) as u64;
        let amount_y = ((liquidity as u128) * (reserve_y as u128) / total_supply) as u64;
        assert!(amount_x > 0 && amount_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        burn_lp<T0, T1>(pair, lp_token);
        update_k_last<T0, T1>(pair);
        let liquidity_removed_event = LiquidityRemoved{
            user      : ctx.sender(), 
            pair      : pair.pair_id(),
            coin_x    : get_type_name<T0>(), 
            coin_y    : get_type_name<T1>(), 
            amount_x  : amount_x, 
            amount_y  : amount_y, 
            liquidity : liquidity, 
            fee       : mint_fee<T0, T1>(pair, treasurer(treasury), ctx),
        };
        emit<LiquidityRemoved>(liquidity_removed_event);
        (extract_x<T0, T1>(pair, amount_x, ctx), extract_y<T0, T1>(pair, amount_y, ctx))
    }
    
    fun burn_lp<T0, T1>(pair: &mut PairMetadata<T0, T1>, lp_token: Coin<LP<T0, T1>>) {
        pair.lp_supply.decrease_supply<LP<T0, T1>>(lp_token.into_balance<LP<T0, T1>>());
    }
    
    public(package) fun create_pair<T0, T1>(ctx: &mut TxContext) : (address, PairMetadata<T0, T1>) {
        let lp_token = LP<T0, T1>{dummy_field: false};
        let pair_metadata = PairMetadata<T0, T1>{
            id        : new_object(ctx), 
            reserve_x : zero<T0>(ctx), 
            reserve_y : zero<T1>(ctx), 
            k_last    : 0, 
            lp_supply : create_supply<LP<T0, T1>>(lp_token),
            creator_liquidity: 0,
            acc_x_fee_for_creator: 0,
            acc_y_fee_for_creator: 0,
            fee_rate  : 0,
        };
        (pair_id(&pair_metadata), pair_metadata)
    }
    
    fun deposit_x<T0, T1>(pair: &mut PairMetadata<T0, T1>, coin_x_in: Coin<T0>) {
        pair.reserve_x.join(coin_x_in);
    }
    
    fun deposit_y<T0, T1>(pair: &mut PairMetadata<T0, T1>, coin_y_in: Coin<T1>) {
        pair.reserve_y.join(coin_y_in);
    }
    
    fun extract_x<T0, T1>(pair: &mut PairMetadata<T0, T1>, amount_x_out: u64, ctx: &mut TxContext) : Coin<T0> {
        pair.reserve_x.split(amount_x_out, ctx)
    }
    
    fun extract_y<T0, T1>(pair: &mut PairMetadata<T0, T1>, amount_y_out: u64, ctx: &mut TxContext) : Coin<T1> {
        pair.reserve_y.split(amount_y_out, ctx)
    }
    
    public fun fee_rate<T0, T1>(pair: &PairMetadata<T0, T1>) : u64 {
        pair.fee_rate
    }
    
    public fun pair_id<T0, T1>(pair: &PairMetadata<T0, T1>) : address {
        pair.id.to_address()
    }
    
    public fun get_lp_name<T0, T1>() : String {
        let mut lp_name = utf8(b"SkyX LP-");
        lp_name.append(get_type_name<T0>());
        lp_name.append_utf8(b"-");
        lp_name.append(get_type_name<T1>());
        lp_name
    }
    
    public fun get_reserves<T0, T1>(pair: &PairMetadata<T0, T1>) : (u64, u64) {
        (pair.reserve_x.value(), pair.reserve_y.value())
    }

    public fun get_creator_fees<T0, T1>(pair: &PairMetadata<T0, T1>) : (u64, u64) {
        (pair.acc_x_fee_for_creator, pair.acc_y_fee_for_creator)
    }
    
    public fun k<T0, T1>(pair: &PairMetadata<T0, T1>) : u128 {
        pair.k_last
    }
    
    public fun mint<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        treasury: &Treasury,
        coin_x: Coin<T0>,
        coin_y: Coin<T1>,
        ctx: &mut TxContext
    ) : Coin<LP<T0, T1>> {
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let amount_x = coin_x.value();
        let amount_y = coin_y.value();
        let total_supply = total_lp_supply<T0, T1>(pair) as u128;
        let liquidity = if (total_supply == 0) {
            let _liquidity = sqrt((amount_x as u128) * (amount_y as u128));
            assert!(_liquidity > (MINIMUM_LIQUIDITY as u128), ERR_INSUFFICIENT_INPUT_AMOUNT);
            public_transfer<Coin<LP<T0, T1>>>(mint_lp<T0, T1>(pair, MINIMUM_LIQUIDITY, ctx), @0x0);
            (_liquidity - (MINIMUM_LIQUIDITY as u128)) as u64
        } else {
            min((amount_x as u128) * total_supply / (reserve_x as u128), (amount_y as u128) * total_supply / (reserve_y as u128)) as u64
        };
        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY_MINT);
        deposit_x<T0, T1>(pair, coin_x);
        deposit_y<T0, T1>(pair, coin_y);
        update_k_last<T0, T1>(pair);
        if (total_supply == 0) pair.creator_liquidity = liquidity;
        let liquidity_added_event = LiquidityAdded{
            user      : ctx.sender(), 
            pair      : pair.pair_id(),
            coin_x    : get_type_name<T0>(), 
            coin_y    : get_type_name<T1>(), 
            amount_x  : amount_x, 
            amount_y  : amount_y, 
            liquidity : liquidity, 
            fee       : mint_fee<T0, T1>(pair, treasurer(treasury), ctx),
        };
        emit<LiquidityAdded>(liquidity_added_event);
        mint_lp<T0, T1>(pair, liquidity, ctx)
    }
    
    fun mint_fee<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        fee_to: address,
        ctx: &mut TxContext
    ) : u64 {
        let mut minted_fee = 0;
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        if (fee_to != @0x0) {
            if (pair.k_last != 0) {
                let root_k = sqrt((reserve_x as u128) * (reserve_y as u128));
                let root_k_last = sqrt(pair.k_last);
                if (root_k > root_k_last) {
                    let _minted_fee = ((total_lp_supply<T0, T1>(pair) as u128) * (root_k - root_k_last) / (root_k * 5 + root_k_last)) as u64; // 1/6 fee
                    minted_fee = _minted_fee;
                    if (_minted_fee > 0) {
                        public_transfer<Coin<LP<T0, T1>>>(mint_lp<T0, T1>(pair, _minted_fee, ctx), fee_to);
                    };
                };
            };
        };
        minted_fee
    }
    
    fun mint_lp<T0, T1>(
        pair: &mut PairMetadata<T0, T1>,
        amount: u64,
        ctx: &mut TxContext
    ) : Coin<LP<T0, T1>> {
        from_balance<LP<T0, T1>>(pair.lp_supply.increase_supply<LP<T0, T1>>(amount), ctx)
    }
    
    public(package) fun set_fee_rate<T0, T1>(pair: &mut PairMetadata<T0, T1>, fee_rate: u64) {
        assert!(fee_rate < MAXIMUM_FEE_RATE, ERR_TOO_LARGE_FEE_RATE);
        pair.fee_rate = fee_rate;
    }
    
    public fun total_lp_supply<T0, T1>(pair: &PairMetadata<T0, T1>) : u64 {
        pair.lp_supply.supply_value()
    }
    
    fun update_k_last<T0, T1>(pair: &mut PairMetadata<T0, T1>) {
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        pair.k_last = (reserve_x as u128) * (reserve_y as u128);
    }
}

