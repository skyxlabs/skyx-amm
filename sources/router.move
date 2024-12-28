module skyx_amm::router {
    use sui::coin::{ Coin, zero, split, join };
    use sui::clock::Clock;
    use sui::transfer::public_transfer;
    use skyx_amm::factory::{ Container, pair_is_created, create_pair, borrow_mut_pair_and_treasury, borrow_mut_pair, borrow_pair };
    use skyx_amm::pair::{ PairMetadata, get_reserves, fee_rate, swap, mint, burn, LP };
    use skyx_amm::treasury::Treasury;
    use skyx_amm::swap_utils::{ is_ordered, get_amount_in, get_amount_out, quote, left_amount };

    public entry fun add_liquidity<T0, T1>(clock: &Clock, cont: &mut Container, coin_x: Coin<T0>, coin_y: Coin<T1>, amount_x_min: u64, amount_y_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        if (!pair_is_created<T0, T1>(cont)) {
            create_pair<T0, T1>(cont, ctx);
        };
        if (is_ordered<T0, T1>()) {
            let (pair, treasury) = borrow_mut_pair_and_treasury<T0, T1>(cont);
            public_transfer<Coin<LP<T0, T1>>>(add_liquidity_direct<T0, T1>(pair, treasury, coin_x, coin_y, amount_x_min, amount_y_min, ctx), recipient);
        } else {
            let (pair, treasury) = borrow_mut_pair_and_treasury<T1, T0>(cont);
            public_transfer<Coin<LP<T1, T0>>>(add_liquidity_direct<T1, T0>(pair, treasury, coin_y, coin_x, amount_y_min, amount_x_min, ctx), recipient);
        };
    }
    
    #[allow(lint(self_transfer))]
    public fun add_liquidity_direct<T0, T1>(pair: &mut PairMetadata<T0, T1>, treasury: &Treasury, mut coin_x: Coin<T0>, mut coin_y: Coin<T1>, amount_x_min: u64, amount_y_min: u64, ctx: &mut TxContext) : Coin<LP<T0, T1>> {
        let amount_x_desired = coin_x.value();
        let amount_y_desired = coin_y.value();
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let (amount_x, amount_y) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_y_optimal = quote(amount_x_desired, reserve_x, reserve_y);
            let (_amount_x, _amount_y) = if (amount_y_optimal <= amount_y_desired) {
                assert!(amount_y_optimal >= amount_y_min, 401);
                (amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = quote(amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x_desired, 403);
                assert!(amount_x_optimal >= amount_x_min, 400);
                (amount_x_optimal, amount_y_desired)
            };
            (_amount_x, _amount_y)
        };
        let recipient = ctx.sender();
        if (amount_x_desired > amount_x) {
            public_transfer<Coin<T0>>(coin_x.split<T0>(amount_x_desired - amount_x, ctx), recipient);
        };
        if (amount_y_desired > amount_y) {
            public_transfer<Coin<T1>>(coin_y.split<T1>(amount_y_desired - amount_y, ctx), recipient);
        };
        mint<T0, T1>(pair, treasury, coin_x, coin_y, ctx)
    }
    
    fun ensure(clock: &Clock, deadline: u64) {
        assert!(deadline >= clock.timestamp_ms(), 404);
    }
    
    public entry fun remove_liquidity<T0, T1>(clock: &Clock, cont: &mut Container, lpToken: Coin<LP<T0, T1>>, amount_x_min: u64, amount_y_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let (pair, treasury) = borrow_mut_pair_and_treasury<T0, T1>(cont);
        let (coin_x, coin_y) = burn<T0, T1>(pair, treasury, lpToken, ctx);
        let _coin_y = coin_y;
        let _coin_x = coin_x;
        assert!(_coin_x.value() >= amount_x_min, 400);
        assert!(_coin_y.value() >= amount_y_min, 401);
        public_transfer<Coin<T0>>(_coin_x, recipient);
        public_transfer<Coin<T1>>(_coin_y, recipient);
    }
    
    public entry fun swap_exact_double_input<T0, T1, T2>(clock: &Clock, cont: &mut Container, coin_in_0: Coin<T0>, coin_in_1: Coin<T1>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let mut coin_out = swap_exact_input_direct<T0, T2>(cont, coin_in_0, ctx);
        join<T2>(&mut coin_out, swap_exact_input_direct<T1, T2>(cont, coin_in_1, ctx));
        assert!(coin_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T2>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_input<T0, T1>(clock: &Clock, cont: &mut Container, coin_in: Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let coin_out = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        assert!(coin_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T1>>(coin_out, recipient);
    }
    
    public fun swap_exact_input_direct<T0, T1>(cont: &mut Container, coin_in: Coin<T0>, ctx: &mut TxContext) : Coin<T1> {
        if (is_ordered<T0, T1>()) {
            swap_exact_x_to_y_direct<T0, T1>(borrow_mut_pair<T0, T1>(cont), coin_in, ctx)
        } else {
            swap_exact_y_to_x_direct<T1, T0>(borrow_mut_pair<T1, T0>(cont), coin_in, ctx)
        }
    }
    
    public entry fun swap_exact_input_double_output<T0, T1, T2>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_out_min_0: u64, amount_out_min_1: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, split(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 405);
        public_transfer<Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, split(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 405);
        public_transfer<Coin<T2>>(coin_out_1, recipient);

        public_transfer<Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_doublehop<T0, T1, T2>(clock: &Clock, cont: &mut Container, coin_in: Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let t = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        let coin_out = swap_exact_input_direct<T1, T2>(cont, t, ctx);
        assert!(coin_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T2>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_input_quadruple_output<T0, T1, T2, T3, T4>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_in_3: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, amount_out_min_3: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 405);
        public_transfer<Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 405);
        public_transfer<Coin<T2>>(coin_out_1, recipient);

        let coin_out_2 = swap_exact_input_direct<T0, T3>(cont, split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_2.value() >= amount_out_min_2, 405);
        public_transfer<Coin<T3>>(coin_out_2, recipient);

        let coin_out_3 = swap_exact_input_direct<T0, T4>(cont, split<T0>(&mut coin_in, amount_in_3, ctx), ctx);
        assert!(coin_out_3.value() >= amount_out_min_3, 405);
        public_transfer<Coin<T4>>(coin_out_3, recipient);

        public_transfer<Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_quintuple_output<T0, T1, T2, T3, T4, T5>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_in_3: u64, amount_in_4: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, amount_out_min_3: u64, amount_out_min_4: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);

        let coin_out_0 = swap_exact_input_direct<T0, T1>(cont, split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_0.value() >= amount_out_min_0, 405);
        public_transfer<Coin<T1>>(coin_out_0, recipient);

        let coin_out_1 = swap_exact_input_direct<T0, T2>(cont, split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_1.value() >= amount_out_min_1, 405);
        public_transfer<Coin<T2>>(coin_out_1, recipient);

        let coin_out_2 = swap_exact_input_direct<T0, T3>(cont, split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_2.value() >= amount_out_min_2, 405);
        public_transfer<Coin<T3>>(coin_out_2, recipient);

        let coin_out_3 = swap_exact_input_direct<T0, T4>(cont, split<T0>(&mut coin_in, amount_in_3, ctx), ctx);
        assert!(coin_out_3.value() >= amount_out_min_3, 405);
        public_transfer<Coin<T4>>(coin_out_3, recipient);

        let coin_out_4 = swap_exact_input_direct<T0, T5>(cont, split<T0>(&mut coin_in, amount_in_4, ctx), ctx);
        assert!(coin_out_4.value() >= amount_out_min_4, 405);
        public_transfer<Coin<T5>>(coin_out_4, recipient);

        public_transfer<Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_triple_output<T0, T1, T2, T3>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_0: u64, amount_in_1: u64, amount_in_2: u64, amount_out_min_0: u64, amount_out_min_1: u64, amount_out_min_2: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);

        let coin_out_min_0 = swap_exact_input_direct<T0, T1>(cont, split<T0>(&mut coin_in, amount_in_0, ctx), ctx);
        assert!(coin_out_min_0.value() >= amount_out_min_0, 405);
        public_transfer<Coin<T1>>(coin_out_min_0, recipient);

        let coin_out_min_1 = swap_exact_input_direct<T0, T2>(cont, split<T0>(&mut coin_in, amount_in_1, ctx), ctx);
        assert!(coin_out_min_1.value() >= amount_out_min_1, 405);
        public_transfer<Coin<T2>>(coin_out_min_1, recipient);

        let coin_out_min_2 = swap_exact_input_direct<T0, T3>(cont, split<T0>(&mut coin_in, amount_in_2, ctx), ctx);
        assert!(coin_out_min_2.value() >= amount_out_min_2, 405);
        public_transfer<Coin<T3>>(coin_out_min_2, recipient);

        public_transfer<Coin<T0>>(coin_in, ctx.sender());
    }
    
    public entry fun swap_exact_input_triplehop<T0, T1, T2, T3>(clock: &Clock, cont: &mut Container, coin_in: Coin<T0>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let t0 = swap_exact_input_direct<T0, T1>(cont, coin_in, ctx);
        let t1 = swap_exact_input_direct<T1, T2>(cont, t0, ctx);
        let coin_out = swap_exact_input_direct<T2, T3>(cont, t1, ctx);
        assert!(coin_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T3>>(coin_out, recipient);
    }
    
    public entry fun swap_exact_output<T0, T1>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let left_amount = left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            public_transfer<Coin<T0>>(split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        public_transfer<Coin<T1>>(swap_exact_output_direct<T0, T1>(cont, coin_in, amount_out, ctx), recipient);
    }

    public fun swap_exact_output_direct<T0, T1>(cont: &mut Container, coin_in: Coin<T0>, amount_out: u64, ctx: &mut TxContext) : Coin<T1> {
        if (is_ordered<T0, T1>()) {
            swap_x_to_exact_y_direct<T0, T1>(borrow_mut_pair<T0, T1>(cont), coin_in, amount_out, ctx)
        } else {
            swap_y_to_exact_x_direct<T1, T0>(borrow_mut_pair<T1, T0>(cont), coin_in, amount_out, ctx)
        }
    }
    
    public entry fun swap_exact_output_doublehop<T0, T1, T2>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let _amount_out = if (is_ordered<T1, T2>()) {
            let pair = borrow_pair<T1, T2>(cont);
            let (reserve_x, reserve_y) = get_reserves<T1, T2>(pair);
            get_amount_in(amount_out, reserve_x, reserve_y, fee_rate<T1, T2>(pair))
        } else {
            let pair = borrow_pair<T2, T1>(cont);
            let (reserve_x, reserve_y) = get_reserves<T2, T1>(pair);
            get_amount_in(amount_out, reserve_y, reserve_x, fee_rate<T2, T1>(pair))
        };
        let left_amount = left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            public_transfer<Coin<T0>>(split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        let t = swap_exact_output_direct<T0, T1>(cont, coin_in, _amount_out, ctx);
        public_transfer<Coin<T2>>(swap_exact_output_direct<T1, T2>(cont, t, amount_out, ctx), recipient);
    }
    
    public entry fun swap_exact_output_triplehop<T0, T1, T2, T3>(clock: &Clock, cont: &mut Container, mut coin_in: Coin<T0>, amount_in_max: u64, amount_out: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let _amount_out_0 = if (is_ordered<T2, T3>()) {
            let pair = borrow_pair<T2, T3>(cont);
            let (reserve_x, reserve_y) = get_reserves<T2, T3>(pair);
            get_amount_in(amount_out, reserve_x, reserve_y, fee_rate<T2, T3>(pair))
        } else {
            let pair = borrow_pair<T3, T2>(cont);
            let (reserve_x, reserve_y) = get_reserves<T3, T2>(pair);
            get_amount_in(amount_out, reserve_y, reserve_x, fee_rate<T3, T2>(pair))
        };
        let _amount_out_1 = if (is_ordered<T1, T2>()) {
            let pair = borrow_pair<T1, T2>(cont);
            let (reserve_x, reserve_y) = get_reserves<T1, T2>(pair);
            get_amount_in(_amount_out_0, reserve_x, reserve_y, fee_rate<T1, T2>(pair))
        } else {
            let pair = borrow_pair<T2, T1>(cont);
            let (reserve_x, reserve_y) = get_reserves<T2, T1>(pair);
            get_amount_in(_amount_out_0, reserve_y, reserve_x, fee_rate<T2, T1>(pair))
        };
        let left_amount = left_amount<T0>(&coin_in, amount_in_max);
        if (left_amount > 0) {
            public_transfer<Coin<T0>>(split<T0>(&mut coin_in, left_amount, ctx), ctx.sender());
        };
        let t0 = swap_exact_output_direct<T0, T1>(cont, coin_in, _amount_out_1, ctx);
        let t1 = swap_exact_output_direct<T1, T2>(cont, t0, _amount_out_0, ctx);
        public_transfer<Coin<T3>>(swap_exact_output_direct<T2, T3>(cont, t1, amount_out, ctx), recipient);
    }
    
    public entry fun swap_exact_quadruple_input<T0, T1, T2, T3, T4>(clock: &Clock, cont: &mut Container, coin_in_0: Coin<T0>, coin_in_1: Coin<T1>, coin_in_2: Coin<T2>, coin_in_3: Coin<T3>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T4>(cont, coin_in_0, ctx);
        join<T4>(&mut amount_out, swap_exact_input_direct<T1, T4>(cont, coin_in_1, ctx));
        join<T4>(&mut amount_out, swap_exact_input_direct<T2, T4>(cont, coin_in_2, ctx));
        join<T4>(&mut amount_out, swap_exact_input_direct<T3, T4>(cont, coin_in_3, ctx));
        assert!(amount_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T4>>(amount_out, recipient);
    }
    
    public entry fun swap_exact_quintuple_input<T0, T1, T2, T3, T4, T5>(clock: &Clock, cont: &mut Container, coin_in_0: Coin<T0>, coin_in_1: Coin<T1>, coin_in_2: Coin<T2>, coin_in_3: Coin<T3>, coin_in_4: Coin<T4>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T5>(cont, coin_in_0, ctx);
        join<T5>(&mut amount_out, swap_exact_input_direct<T1, T5>(cont, coin_in_1, ctx));
        join<T5>(&mut amount_out, swap_exact_input_direct<T2, T5>(cont, coin_in_2, ctx));
        join<T5>(&mut amount_out, swap_exact_input_direct<T3, T5>(cont, coin_in_3, ctx));
        join<T5>(&mut amount_out, swap_exact_input_direct<T4, T5>(cont, coin_in_4, ctx));
        assert!(amount_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T5>>(amount_out, recipient);
    }
    
    public entry fun swap_exact_triple_input<T0, T1, T2, T3>(clock: &Clock, cont: &mut Container, coin_in_0: Coin<T0>, coin_in_1: Coin<T1>, coin_in_2: Coin<T2>, amount_out_min: u64, recipient: address, deadline: u64, ctx: &mut TxContext) {
        ensure(clock, deadline);
        let mut amount_out = swap_exact_input_direct<T0, T3>(cont, coin_in_0, ctx);
        join<T3>(&mut amount_out, swap_exact_input_direct<T1, T3>(cont, coin_in_1, ctx));
        join<T3>(&mut amount_out, swap_exact_input_direct<T2, T3>(cont, coin_in_2, ctx));
        assert!(amount_out.value() >= amount_out_min, 405);
        public_transfer<Coin<T3>>(amount_out, recipient);
    }
    
    public fun swap_exact_x_to_y_direct<T0, T1>(pair: &mut PairMetadata<T0, T1>, coin_x: Coin<T0>, ctx: &mut TxContext) : Coin<T1> {
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let fee_rate = fee_rate<T0, T1>(pair);
        let amount_in = coin_x.value();
        let (coin_x_out, coin_y_out) = swap<T0, T1>(pair, coin_x, 0, zero<T1>(ctx), get_amount_out(amount_in, reserve_x, reserve_y, fee_rate), ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_x_out.value() == 0 && _coin_y_out.value() > 0, 405);
        _coin_x_out.destroy_zero();
        _coin_y_out
    }
    
    public fun swap_exact_y_to_x_direct<T0, T1>(pair: &mut PairMetadata<T0, T1>, coin_y: Coin<T1>, ctx: &mut TxContext) : Coin<T0> {
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let fee_rate = fee_rate<T0, T1>(pair);
        let (coin_x_out, coin_y_out) = swap<T0, T1>(pair, zero<T0>(ctx), get_amount_out(coin_y.value(), reserve_y, reserve_x, fee_rate), coin_y, 0, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_y_out.value() == 0 && _coin_x_out.value() > 0, 405);
        _coin_y_out.destroy_zero();
        _coin_x_out
    }
    
    #[allow(lint(self_transfer))]
    public fun swap_x_to_exact_y_direct<T0, T1>(pair: &mut PairMetadata<T0, T1>, mut coin_x: Coin<T0>, amount_y_out: u64, ctx: &mut TxContext) : Coin<T1> {
        let balance_x = coin_x.value();
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let amount_x_in = get_amount_in(amount_y_out, reserve_x, reserve_y, fee_rate<T0, T1>(pair));
        assert!(amount_x_in <= balance_x, 406);
        if (balance_x > amount_x_in) {
            public_transfer<Coin<T0>>(split<T0>(&mut coin_x, balance_x - amount_x_in, ctx), ctx.sender());
        };
        let (coin_x_out, coin_y_out) = swap<T0, T1>(pair, coin_x, 0, zero<T1>(ctx), amount_y_out, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_x_out.value() == 0 && _coin_y_out.value() > 0, 405);
        _coin_x_out.destroy_zero();
        _coin_y_out
    }
    
    #[allow(lint(self_transfer))]
    public fun swap_y_to_exact_x_direct<T0, T1>(pair: &mut PairMetadata<T0, T1>, mut coin_y: Coin<T1>, amount_x_out: u64, ctx: &mut TxContext) : Coin<T0> {
        let balance_y = coin_y.value();
        let (reserve_x, reserve_y) = get_reserves<T0, T1>(pair);
        let amount_y_in = get_amount_in(amount_x_out, reserve_y, reserve_x, fee_rate<T0, T1>(pair));
        assert!(amount_y_in <= balance_y, 406);
        if (balance_y > amount_y_in) {
            public_transfer<Coin<T1>>(split<T1>(&mut coin_y, balance_y - amount_y_in, ctx), ctx.sender());
        };
        let (coin_x_out, coin_y_out) = swap<T0, T1>(pair, zero<T0>(ctx), amount_x_out, coin_y, 0, ctx);
        let _coin_y_out = coin_y_out;
        let _coin_x_out = coin_x_out;
        assert!(_coin_y_out.value() == 0 && _coin_x_out.value() > 0, 405);
        _coin_y_out.destroy_zero();
        _coin_x_out
    }
}

