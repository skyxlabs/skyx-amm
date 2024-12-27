module skyx_amm::factory {
    use std::string;
    use sui::bag;
    use sui::event;

    const ERR_ALREADY_EXIST_PAIR: u64 = 0;
    const ERR_INCORRECT_ORDER: u64 = 1;

    const DEFAULT_FEE_RATE: u64 = 30; // 0.3%

    public struct Container has key {
        id: object::UID,
        pairs: bag::Bag,
        treasury: skyx_amm::treasury::Treasury,
    }
    
    public struct AdminCap has store, key {
        id: object::UID,
    }
    
    public struct PairCreated has copy, drop {
        user: address,
        pair: ID,
        coin_x: string::String,
        coin_y: string::String,
    }
    
    public struct FeeChanged has copy, drop {
        user: address,
        pair: ID,
        coin_x: string::String,
        coin_y: string::String,
        fee_rate: u64,
    }
    
    public fun create_pair<T0, T1>(cont: &mut Container, ctx: &mut tx_context::TxContext) {
        let pair_id = if (skyx_amm::swap_utils::is_ordered<T0, T1>()) {
            let _pair = skyx_amm::pair::get_lp_name<T0, T1>();
            assert!(!cont.pairs.contains_with_type<string::String, skyx_amm::pair::PairMetadata<T0, T1>>(_pair), ERR_ALREADY_EXIST_PAIR);
            let (_pair_id, _pair_metadata) = skyx_amm::pair::create_pair<T0, T1>(ctx);
            cont.pairs.add<string::String, skyx_amm::pair::PairMetadata<T0, T1>>(_pair, _pair_metadata);
            _pair_id
        } else {
            let _pair = skyx_amm::pair::get_lp_name<T1, T0>();
            assert!(!cont.pairs.contains_with_type<string::String, skyx_amm::pair::PairMetadata<T1, T0>>(_pair), ERR_ALREADY_EXIST_PAIR);
            let (_pair_id, _pair_metadata) = skyx_amm::pair::create_pair<T1, T0>(ctx);
            cont.pairs.add<string::String, skyx_amm::pair::PairMetadata<T1, T0>>(_pair, _pair_metadata);
            _pair_id
        };
        let pair_created_event = PairCreated{
            user   : ctx.sender(), 
            pair   : pair_id, 
            coin_x : skyx_amm::type_helper::get_type_name<T0>(), 
            coin_y : skyx_amm::type_helper::get_type_name<T1>(),
        };
        event::emit<PairCreated>(pair_created_event);
        set_fee_rate_<T0, T1>(cont, DEFAULT_FEE_RATE, ctx);
    }
    
    #[allow(unused_variable)]
    public entry fun set_fee_rate<T0, T1>(admin_cap: &mut AdminCap, cont: &mut Container, fee_rate: u64, ctx: &mut tx_context::TxContext) {
        set_fee_rate_<T0, T1>(cont, fee_rate, ctx);
    }
    
    public fun borrow_mut_pair<T0, T1>(cont: &mut Container) : &mut skyx_amm::pair::PairMetadata<T0, T1> {
        assert!(skyx_amm::swap_utils::is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        &mut cont.pairs[skyx_amm::pair::get_lp_name<T0, T1>()]
    }
    
    public fun borrow_mut_pair_and_treasury<T0, T1>(cont: &mut Container) : (&mut skyx_amm::pair::PairMetadata<T0, T1>, &skyx_amm::treasury::Treasury) {
        assert!(skyx_amm::swap_utils::is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        (&mut cont.pairs[skyx_amm::pair::get_lp_name<T0, T1>()], &cont.treasury)
    }
    
    public fun borrow_pair<T0, T1>(cont: &Container) : &skyx_amm::pair::PairMetadata<T0, T1> {
        assert!(skyx_amm::swap_utils::is_ordered<T0, T1>(), ERR_INCORRECT_ORDER);
        &cont.pairs[skyx_amm::pair::get_lp_name<T0, T1>()]
    }
    
    public fun borrow_treasury(cont: &Container) : &skyx_amm::treasury::Treasury {
        &cont.treasury
    }
    
    fun init(ctx: &mut tx_context::TxContext) {
        let cont = Container{
            id       : object::new(ctx), 
            pairs    : bag::new(ctx), 
            treasury : skyx_amm::treasury::new(@0x0),
        };
        transfer::share_object<Container>(cont);
        let admin_cap = AdminCap{id: object::new(ctx)};
        transfer::transfer<AdminCap>(admin_cap, ctx.sender());
    }
    
    public fun pair_is_created<T0, T1>(cont: &Container) : bool {
        skyx_amm::swap_utils::is_ordered<T0, T1>() && cont.pairs.contains_with_type<string::String, skyx_amm::pair::PairMetadata<T0, T1>>(skyx_amm::pair::get_lp_name<T0, T1>()) || cont.pairs.contains_with_type<string::String, skyx_amm::pair::PairMetadata<T1, T0>>(skyx_amm::pair::get_lp_name<T1, T0>())
    }
    
    fun set_fee_rate_<T0, T1>(cont: &mut Container, fee_rate: u64, ctx: &tx_context::TxContext) {
        let pair_id = if (skyx_amm::swap_utils::is_ordered<T0, T1>()) {
            let _pair_metadata: &mut skyx_amm::pair::PairMetadata<T0, T1> = &mut cont.pairs[skyx_amm::pair::get_lp_name<T0, T1>()];
            skyx_amm::pair::set_fee_rate<T0, T1>(_pair_metadata, fee_rate);
            _pair_metadata.pair_id()
        } else {
            let _pair_metadata: &mut skyx_amm::pair::PairMetadata<T1, T0> = &mut cont.pairs[skyx_amm::pair::get_lp_name<T1, T0>()];
            skyx_amm::pair::set_fee_rate<T1, T0>(_pair_metadata, fee_rate);
            _pair_metadata.pair_id()
        };
        let fee_changed_event = FeeChanged{
            user     : ctx.sender(), 
            pair     : pair_id, 
            coin_x   : skyx_amm::type_helper::get_type_name<T0>(), 
            coin_y   : skyx_amm::type_helper::get_type_name<T1>(), 
            fee_rate : fee_rate,
        };
        event::emit<FeeChanged>(fee_changed_event);
    }
    
    #[allow(unused_variable)]
    public entry fun set_fee_to(admin_cap: &mut AdminCap, cont: &mut Container, fee_to: address) {
        skyx_amm::treasury::appoint(&mut cont.treasury, fee_to);
    }
}

