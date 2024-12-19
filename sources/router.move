module skyx_amm::router {
    use sui::coin;
    use sui::clock;

    public entry fun add_liquidity<T0, T1>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_x: coin::Coin<T0>, coin_y: coin::Coin<T1>, amount_x_min: u64, amount_y_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        if (!skyx_amm::factory::pair_is_created<T0, T1>(cont)) {
            skyx_amm::factory::create_pair<T0, T1>(cont, ctx);
        };
        if (skyx_amm::swap_utils::is_ordered<T0, T1>()) {
            let (pair, treasury) = skyx_amm::factory::borrow_mut_pair_and_treasury<T0, T1>(cont);
            transfer::public_transfer<coin::Coin<skyx_amm::pair::LP<T0, T1>>>(add_liquidity_direct<T0, T1>(pair, treasury, coin_x, coin_y, amount_x_min, amount_y_min, ctx), recipient);
        } else {
            let (pair, treasury) = skyx_amm::factory::borrow_mut_pair_and_treasury<T1, T0>(cont);
            transfer::public_transfer<coin::Coin<skyx_amm::pair::LP<T1, T0>>>(add_liquidity_direct<T1, T0>(pair, treasury, coin_y, coin_x, amount_y_min, amount_x_min, ctx), recipient);
        };
    }
    
    #[allow(lint(self_transfer))]
    public fun add_liquidity_direct<T0, T1>(pair: &mut skyx_amm::pair::PairMetadata<T0, T1>, treasury: &skyx_amm::treasury::Treasury, mut coin_x: coin::Coin<T0>, mut coin_y: coin::Coin<T1>, amount_x_min: u64, amount_y_min: u64, ctx: &mut tx_context::TxContext) : coin::Coin<skyx_amm::pair::LP<T0, T1>> {
        let amount_x_desired = coin_x.value();
        let amount_y_desired = coin_y.value();
        let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T0, T1>(pair);
        let (amount_x, amount_y) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_y_optimal = skyx_amm::swap_utils::quote(amount_x_desired, reserve_x, reserve_y);
            let (_amount_x, _amount_y) = if (amount_y_optimal <= amount_y_desired) {
                assert!(amount_y_optimal >= amount_y_min, 1);
                (amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = skyx_amm::swap_utils::quote(amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x_desired, 3);
                assert!(amount_x_optimal >= amount_x_min, 0);
                (amount_x_optimal, amount_y_desired)
            };
            (_amount_x, _amount_y)
        };
        let recipient = ctx.sender();
        if (amount_x_desired > amount_x) {
            transfer::public_transfer<coin::Coin<T0>>(coin_x.split<T0>(amount_x_desired - amount_x, ctx), recipient);
        };
        if (amount_y_desired > amount_y) {
            transfer::public_transfer<coin::Coin<T1>>(coin_y.split<T1>(amount_y_desired - amount_y, ctx), recipient);
        };
        skyx_amm::pair::mint<T0, T1>(pair, treasury, coin_x, coin_y, ctx)
    }
    
    fun ensure(clock: &clock::Clock, deadline: u64) {
        assert!(deadline >= clock.timestamp_ms(), 4);
    }
    
    public entry fun remove_liquidity<T0, T1>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, lpToken: coin::Coin<skyx_amm::pair::LP<T0, T1>>, amount_x_min: u64, amount_y_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let (pair, treasury) = skyx_amm::factory::borrow_mut_pair_and_treasury<T0, T1>(cont);
        let (coin_x, coin_y) = skyx_amm::pair::burn<T0, T1>(pair, treasury, lpToken, ctx);
        let _coin_y = coin_y;
        let _coin_x = coin_x;
        assert!(_coin_x.value() >= amount_x_min, 0);
        assert!(_coin_y.value() >= amount_y_min, 1);
        transfer::public_transfer<coin::Coin<T0>>(_coin_x, recipient);
        transfer::public_transfer<coin::Coin<T1>>(_coin_y, recipient);
    }
    
    public entry fun swap_exact_double_input<T0, T1, T2>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in_0: coin::Coin<T0>, coin_in_1: coin::Coin<T1>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let mut coin_out = swap_exact_input_direct<T0, T2>(cont, coin_in_0, ctx);
        coin::join<T2>(&mut coin_out, swap_exact_input_direct<T1, T2>(cont, coin_in_1, ctx));
        assert!(coin_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_input<T0, T1>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in: coin::Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let coin_out = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        assert!(coin_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T1>>(coin_out, recipient);
    }
    
    public fun swap_exact_input_direct<T0, T1>(cont: &mut skyx_amm::factory::Container, coin_in: coin::Coin<T0>, ctx: &mut tx_context::TxContext) : coin::Coin<T1> {
        if (skyx_amm::swap_utils::is_ordered<T0, T1>()) {
            swap_exact_x_to_y_direct<T0, T1>(skyx_amm::factory::borrow_mut_pair<T0, T1>(cont), coin_in, ctx)
        } else {
            swap_exact_y_to_x_direct<T1, T0>(skyx_amm::factory::borrow_mut_pair<T1, T0>(cont), coin_in, ctx)
        }
    }
    
    public entry fun swap_exact_input_double_output<T0, T1, T2>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_out_min_0: u64, amount_out_min_1: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, coin::split(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 5);
        transfer::public_transfer<coin::Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, coin::split(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out_1, recipient);

        transfer::public_transfer<coin::Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_doublehop<T0, T1, T2>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in: coin::Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let t = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        let coin_out = swap_exact_input_direct<T1, T2>(cont, t, ctx);
        assert!(coin_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_input_quadruple_output<T0, T1, T2, T3, T4>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_in_3: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, amount_out_min_3: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, coin::split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 5);
        transfer::public_transfer<coin::Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, coin::split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out_1, recipient);

        let coin_out_2 = swap_exact_input_direct<T0, T3>(cont, coin::split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_2.value() >= amount_out_min_2, 5);
        transfer::public_transfer<coin::Coin<T3>>(coin_out_2, recipient);

        let coin_out_3 = swap_exact_input_direct<T0, T4>(cont, coin::split<T0>(&mut coin_in, amount_in_3, ctx), ctx);
        assert!(coin_out_3.value() >= amount_out_min_3, 5);
        transfer::public_transfer<coin::Coin<T4>>(coin_out_3, recipient);

        transfer::public_transfer<coin::Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_quintuple_output<T0, T1, T2, T3, T4, T5>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_in_3: u64, amount_in_4: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, amount_out_min_3: u64, amount_out_min_4: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, coin::split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 5);
        transfer::public_transfer<coin::Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, coin::split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out_1, recipient);

        let coin_out_2 = swap_exact_input_direct<T0, T3>(cont, coin::split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_2.value() >= amount_out_min_2, 5);
        transfer::public_transfer<coin::Coin<T3>>(coin_out_2, recipient);

        let coin_out_3 = swap_exact_input_direct<T0, T4>(cont, coin::split<T0>(&mut coin_in, amount_in_3, ctx), ctx);
        assert!(coin_out_3.value() >= amount_out_min_3, 5);
        transfer::public_transfer<coin::Coin<T4>>(coin_out_3, recipient);

        let coin_out_4 = swap_exact_input_direct<T0, T5>(cont, coin::split<T0>(&mut coin_in, amount_in_4, ctx), ctx);
        assert!(coin_out_4.value() >= amount_out_min_4, 5);
        transfer::public_transfer<coin::Coin<T5>>(coin_out_4, recipient);

        transfer::public_transfer<coin::Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_triple_output<T0, T1, T2, T3>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);

        let coin_out_min_0 = swap_exact_input_direct<T0, T1>(cont, coin::split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_min_0.value() >= amount_out_min_0, 5);
        transfer::public_transfer<coin::Coin<T1>>(coin_out_min_0, recipient);

        let coin_out_min_1 = swap_exact_input_direct<T0, T2>(cont, coin::split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_min_1.value() >= amount_out_min_1, 5);
        transfer::public_transfer<coin::Coin<T2>>(coin_out_min_1, recipient);

        let coin_out_min_2 = swap_exact_input_direct<T0, T3>(cont, coin::split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_min_2.value() >= amount_out_min_2, 5);
        transfer::public_transfer<coin::Coin<T3>>(coin_out_min_2, recipient);

        transfer::public_transfer<coin::Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_triplehop<T0, T1, T2, T3>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in: coin::Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let t0 = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        let t1 = swap_exact_input_direct<T1, T2>(cont, t0, ctx);
        let coin_out = swap_exact_input_direct<T2, T3>(cont, t1, ctx);
        assert!(coin_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T3>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_output<T0, T1>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let left_amount = skyx_amm::swap_utils::left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            transfer::public_transfer<coin::Coin<T0>>(coin::split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        transfer::public_transfer<coin::Coin<T1>>(swap_exact_output_direct<T0, T1>(cont, coin_in, amount_out, ctx), recipient);
    }

    public fun swap_exact_output_direct<T0, T1>(cont: &mut skyx_amm::factory::Container, coin_in: coin::Coin<T0>, amount_out: u64, ctx: &mut tx_context::TxContext) : coin::Coin<T1> {
        if (skyx_amm::swap_utils::is_ordered<T0, T1>()) {
            swap_x_to_exact_y_direct<T0, T1>(skyx_amm::factory::borrow_mut_pair<T0, T1>(cont), coin_in, amount_out, ctx)
        } else {
            swap_y_to_exact_x_direct<T1, T0>(skyx_amm::factory::borrow_mut_pair<T1, T0>(cont), coin_in, amount_out, ctx)
        }
    }
    
    public entry fun swap_exact_output_doublehop<T0, T1, T2>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let _amount_out = if (skyx_amm::swap_utils::is_ordered<T1, T2>()) {
            let pair = skyx_amm::factory::borrow_pair<T1, T2>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T1, T2>(pair);
            skyx_amm::swap_utils::get_amount_in(amount_out, reserve_x, reserve_y, skyx_amm::pair::fee_rate<T1, T2>(pair))
        } else {
            let pair = skyx_amm::factory::borrow_pair<T2, T1>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T2, T1>(pair);
            skyx_amm::swap_utils::get_amount_in(amount_out, reserve_y, reserve_x, skyx_amm::pair::fee_rate<T2, T1>(pair))
        };
        let left_amount = skyx_amm::swap_utils::left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            transfer::public_transfer<coin::Coin<T0>>(coin::split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        let t = swap_exact_output_direct<T0, T1>(cont, coin_in, _amount_out, ctx);
        transfer::public_transfer<coin::Coin<T2>>(swap_exact_output_direct<T1, T2>(cont, t, amount_out, ctx), recipient);
    }
    
    public entry fun swap_exact_output_triplehop<T0, T1, T2, T3>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, mut coin_in: coin::Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let _amount_out_0 = if (skyx_amm::swap_utils::is_ordered<T2, T3>()) {
            let pair = skyx_amm::factory::borrow_pair<T2, T3>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T2, T3>(pair);
            skyx_amm::swap_utils::get_amount_in(amount_out, reserve_x, reserve_y, skyx_amm::pair::fee_rate<T2, T3>(pair))
        } else {
            let pair = skyx_amm::factory::borrow_pair<T3, T2>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T3, T2>(pair);
            skyx_amm::swap_utils::get_amount_in(amount_out, reserve_y, reserve_x, skyx_amm::pair::fee_rate<T3, T2>(pair))
        };
        let _amount_out_1 = if (skyx_amm::swap_utils::is_ordered<T1, T2>()) {
            let pair = skyx_amm::factory::borrow_pair<T1, T2>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T1, T2>(pair);
            skyx_amm::swap_utils::get_amount_in(_amount_out_0, reserve_x, reserve_y, skyx_amm::pair::fee_rate<T1, T2>(pair))
        } else {
            let pair = skyx_amm::factory::borrow_pair<T2, T1>(cont);
            let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T2, T1>(pair);
            skyx_amm::swap_utils::get_amount_in(_amount_out_0, reserve_y, reserve_x, skyx_amm::pair::fee_rate<T2, T1>(pair))
        };
        let left_amount = skyx_amm::swap_utils::left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            transfer::public_transfer<coin::Coin<T0>>(coin::split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        let t0 = swap_exact_output_direct<T0, T1>(cont, coin_in, _amount_out_1, ctx);
        let t1 = swap_exact_output_direct<T1, T2>(cont, t0, _amount_out_0, ctx);
        transfer::public_transfer<coin::Coin<T3>>(swap_exact_output_direct<T2, T3>(cont, t1, amount_out, ctx), recipient);
    }
    
    public entry fun swap_exact_quadruple_input<T0, T1, T2, T3, T4>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in_0: coin::Coin<T0>, coin_in_1: coin::Coin<T1>, coin_in_2: coin::Coin<T2>, coin_in_3: coin::Coin<T3>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T4>(cont, coin_in_0, ctx);
        coin::join<T4>(&mut amount_out, swap_exact_input_direct<T1, T4>(cont, coin_in_1, ctx));
        coin::join<T4>(&mut amount_out, swap_exact_input_direct<T2, T4>(cont, coin_in_2, ctx));
        coin::join<T4>(&mut amount_out, swap_exact_input_direct<T3, T4>(cont, coin_in_3, ctx));
        assert!(amount_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T4>>(amount_out, recipient);
    }
    
    public entry fun swap_exact_quintuple_input<T0, T1, T2, T3, T4, T5>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in_0: coin::Coin<T0>, coin_in_1: coin::Coin<T1>, coin_in_2: coin::Coin<T2>, coin_in_3: coin::Coin<T3>, coin_in_4: coin::Coin<T4>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T5>(cont, coin_in_0, ctx);
        coin::join<T5>(&mut amount_out, swap_exact_input_direct<T1, T5>(cont, coin_in_1, ctx));
        coin::join<T5>(&mut amount_out, swap_exact_input_direct<T2, T5>(cont, coin_in_2, ctx));
        coin::join<T5>(&mut amount_out, swap_exact_input_direct<T3, T5>(cont, coin_in_3, ctx));
        coin::join<T5>(&mut amount_out, swap_exact_input_direct<T4, T5>(cont, coin_in_4, ctx));
        assert!(amount_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T5>>(amount_out, recipient);
    }
    
    public entry fun swap_exact_triple_input<T0, T1, T2, T3>(clock: &clock::Clock, cont: &mut skyx_amm::factory::Container, coin_in_0: coin::Coin<T0>, coin_in_1: coin::Coin<T1>, coin_in_2: coin::Coin<T2>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut tx_context::TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T3>(cont, coin_in_0, ctx);
        coin::join<T3>(&mut amount_out, swap_exact_input_direct<T1, T3>(cont, coin_in_1, ctx));
        coin::join<T3>(&mut amount_out, swap_exact_input_direct<T2, T3>(cont, coin_in_2, ctx));
        assert!(amount_out.value() >= amount_out_min, 5);
        transfer::public_transfer<coin::Coin<T3>>(amount_out, recipient);
    }
    
    public fun swap_exact_x_to_y_direct<T0, T1>(pair: &mut skyx_amm::pair::PairMetadata<T0, T1>, coin_x: coin::Coin<T0>, ctx: &mut tx_context::TxContext) : coin::Coin<T1> {
        let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T0, T1>(pair);
        let fee_rate = skyx_amm::pair::fee_rate<T0, T1>(pair);
        let amount_in = coin_x.value();
        let (coin_x_out, coin_y_out) = skyx_amm::pair::swap<T0, T1>(pair, coin_x, 0, coin::zero<T1>(ctx), skyx_amm::swap_utils::get_amount_out(amount_in, reserve_x, reserve_y, fee_rate), ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_x_out.value() == 0 && _coin_y_out.value() > 0, 5);
        _coin_x_out.destroy_zero();
        _coin_y_out
    }
    
    public fun swap_exact_y_to_x_direct<T0, T1>(pair: &mut skyx_amm::pair::PairMetadata<T0, T1>, coin_y: coin::Coin<T1>, ctx: &mut tx_context::TxContext) : coin::Coin<T0> {
        let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T0, T1>(pair);
        let fee_rate = skyx_amm::pair::fee_rate<T0, T1>(pair);
        let (coin_x_out, coin_y_out) = skyx_amm::pair::swap<T0, T1>(pair, coin::zero<T0>(ctx), skyx_amm::swap_utils::get_amount_out(coin_y.value(), reserve_y, reserve_x, fee_rate), coin_y, 0, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_y_out.value() == 0 && _coin_x_out.value() > 0, 5);
        _coin_y_out.destroy_zero();
        _coin_x_out
    }
    
    #[allow(lint(self_transfer))]
    public fun swap_x_to_exact_y_direct<T0, T1>(pair: &mut skyx_amm::pair::PairMetadata<T0, T1>, mut coin_x: coin::Coin<T0>, amount_y_out: u64, ctx: &mut tx_context::TxContext) : coin::Coin<T1> {
        let balance_x = coin_x.value();
        let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T0, T1>(pair);
        let amount_x_in = skyx_amm::swap_utils::get_amount_in(amount_y_out, reserve_x, reserve_y, skyx_amm::pair::fee_rate<T0, T1>(pair));
        assert!(amount_x_in <= balance_x, 6);
        if (balance_x > amount_x_in) {
            transfer::public_transfer<coin::Coin<T0>>(coin::split<T0>(&mut coin_x, balance_x - amount_x_in, ctx), ctx.sender());
        };
        let (coin_x_out, coin_y_out) = skyx_amm::pair::swap<T0, T1>(pair, coin_x, 0, coin::zero<T1>(ctx), amount_y_out, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_x_out.value() == 0 && _coin_y_out.value() > 0, 5);
        _coin_x_out.destroy_zero();
        _coin_y_out
    }
    
    #[allow(lint(self_transfer))]
    public fun swap_y_to_exact_x_direct<T0, T1>(pair: &mut skyx_amm::pair::PairMetadata<T0, T1>, mut coin_y: coin::Coin<T1>, amount_x_out: u64, ctx: &mut tx_context::TxContext) : coin::Coin<T0> {
        let balance_y = coin_y.value();
        let (reserve_x, reserve_y) = skyx_amm::pair::get_reserves<T0, T1>(pair);
        let amount_y_in = skyx_amm::swap_utils::get_amount_in(amount_x_out, reserve_y, reserve_x, skyx_amm::pair::fee_rate<T0, T1>(pair));
        assert!(amount_y_in <= balance_y, 6);
        if (balance_y > amount_y_in) {
            transfer::public_transfer<coin::Coin<T1>>(coin::split<T1>(&mut coin_y, balance_y - amount_y_in, ctx), ctx.sender());
        };
        let (coin_x_out, coin_y_out) = skyx_amm::pair::swap<T0, T1>(pair, coin::zero<T0>(ctx), amount_x_out, coin_y, 0, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_y_out.value() == 0 && _coin_x_out.value() > 0, 5);
        _coin_y_out.destroy_zero();
        _coin_x_out
    }
}

