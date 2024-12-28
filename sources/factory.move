module skyx_amm::factory {
    use std::string::String;
    use sui::object::new as new_object;
    use sui::bag::{ Bag, new as new_bag };
    use sui::transfer::{ transfer, share_object };
    use sui::event::emit;
    use skyx_amm::type_helper::get_type_name;
    use skyx_amm::swap_utils::{ is_ordered };
    use skyx_amm::treasury::{ Treasury, new as new_treasury, appoint };
    use skyx_amm::pair::{ PairMetadata, get_lp_name, create_pair as init_pair, set_fee_rate as set_pair_fee_rate };

    const ERR_ALREADY_EXIST_PAIR: u64 = 400;
    const ERR_INCORRECT_ORDER: u64 = 401;

    const DEFAULT_FEE_RATE: u64 = 30; // 0.3%

    public struct Container has key {
        id: UID,
        pairs: Bag,
        treasury: Treasury,
    }
    
    public struct AdminCap has store, key {
        id: UID,
    }
    
    public struct PairCreated has copy, drop {
        user: address,
        pair: address,
        coin_x: String,
        coin_y: String,
    }
    
    public struct FeeChanged has copy, drop {
        user: address,
        pair: address,
        coin_x: String,
        coin_y: String,
        fee_rate: u64,
    }
    
    public fun create_pair<T0, T1>(cont: &mut Container, ctx: &mut TxContext) {
        let pair_id = if (is_ordered<T0, T1>()) {
            let _pair = get_lp_name<T0, T1>();
            assert!(!cont.pairs.contains_with_type<String, PairMetadata<T0, T1>>(_pair), ERR_ALREADY_EXIST_PAIR);
            let (_pair_id, _pair_metadata) = init_pair<T0, T1>(ctx);
            cont.pairs.add<String, PairMetadata<T0, T1>>(_pair, _pair_metadata);
            _pair_id
        } else {
            let _pair = get_lp_name<T1, T0>();
            assert!(!cont.pairs.contains_with_type<String, PairMetadata<T1, T0>>(_pair), ERR_ALREADY_EXIST_PAIR);
            let (_pair_id, _pair_metadata) = init_pair<T1, T0>(ctx);
            cont.pairs.add<String, PairMetadata<T1, T0>>(_pair, _pair_metadata);
            _pair_id
        };
        let pair_created_event = PairCreated{
            user   : ctx.sender(), 
            pair   : pair_id, 
            coin_x : get_type_name<T0>(), 
            coin_y : get_type_name<T1>(),
        };
        emit<PairCreated>(pair_created_event);
        set_fee_rate_<T0, T1>(cont, DEFAULT_FEE_RATE, ctx);
    }
    
    #[allow(unused_variable)]
    public entry fun set_fee_rate<T0, T1>(admin_cap: &mut AdminCap, cont: &mut Container, fee_rate: u64, ctx: &mut TxContext) {
        set_fee_rate_<T0, T1>(cont, fee_rate, ctx);
    }
    
    public fun borrow_mut_pair<T0, T1>(cont: &mut Container) : &mut PairMetadata<T0, T1> {
        assert!(is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        &mut cont.pairs[get_lp_name<T0, T1>()]
    }
    
    public fun borrow_mut_pair_and_treasury<T0, T1>(cont: &mut Container) : (&mut PairMetadata<T0, T1>, &Treasury) {
        assert!(is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        (&mut cont.pairs[get_lp_name<T0, T1>()], &cont.treasury)
    }
    
    public fun borrow_pair<T0, T1>(cont: &Container) : &PairMetadata<T0, T1> {
        assert!(is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        &cont.pairs[get_lp_name<T0, T1>()]
    }
    
    public fun borrow_treasury(cont: &Container) : &Treasury {
        &cont.treasury
    }
    
    fun init(ctx: &mut TxContext) {
        let cont = Container{
            id       : new_object(ctx), 
            pairs    : new_bag(ctx), 
            treasury : new_treasury(@0x0),
        };
        share_object<Container>(cont);
        let admin_cap = AdminCap{id: new_object(ctx)};
        transfer<AdminCap>(admin_cap, ctx.sender());
    }
    
    public fun pair_is_created<T0, T1>(cont: &Container) : bool {
        is_ordered<T0, T1>() && cont.pairs.contains_with_type<String, PairMetadata<T0, T1>>(get_lp_name<T0, T1>()) || cont.pairs.contains_with_type<String, PairMetadata<T1, T0>>(get_lp_name<T1, T0>())
    }
    
    fun set_fee_rate_<T0, T1>(cont: &mut Container, fee_rate: u64, ctx: &TxContext) {
        let pair_id = if (is_ordered<T0, T1>()) {
            let _pair_metadata: &mut PairMetadata<T0, T1> = &mut cont.pairs[get_lp_name<T0, T1>()];
            set_pair_fee_rate<T0, T1>(_pair_metadata, fee_rate);
            _pair_metadata.pair_id()
        } else {
            let _pair_metadata: &mut PairMetadata<T1, T0> = &mut cont.pairs[get_lp_name<T1, T0>()];
            set_pair_fee_rate<T1, T0>(_pair_metadata, fee_rate);
            _pair_metadata.pair_id()
        };
        let fee_changed_event = FeeChanged{
            user     : ctx.sender(), 
            pair     : pair_id, 
            coin_x   : get_type_name<T0>(), 
            coin_y   : get_type_name<T1>(), 
            fee_rate : fee_rate,
        };
        emit<FeeChanged>(fee_changed_event);
    }
    
    #[allow(unused_variable)]
    public entry fun set_fee_to(admin_cap: &mut AdminCap, cont: &mut Container, fee_to: address) {
        appoint(&mut cont.treasury, fee_to);
    }
}

