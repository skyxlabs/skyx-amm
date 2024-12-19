module skyx_amm::swap_utils {
    use std::ascii;
    use std::type_name;
    use sui::coin;

    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 0;
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 1;
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 2;
    const ERR_IDENTICAL_TOKENS: u64 = 3;

    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ) : u64 {
        assert!(amount_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        (((reserve_in as u256) * (amount_out as u256) * (10000 as u256) / ((reserve_out as u256) - (amount_out as u256)) * ((10000 as u256) - (swap_fee as u256))) as u64) + 1
    }
    
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ) : u64 {
        assert!(amount_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_in_with_fee = (amount_in as u256) * ((10000 as u256) - (swap_fee as u256));
        (amount_in_with_fee * (reserve_out as u256) / ((reserve_in as u256) * (10000 as u256) + amount_in_with_fee)) as u64
    }
    
    public fun is_ordered<T0, T1>() : bool {
        let result = skyx_amm::comparator::compare_u8_vector(ascii::into_bytes(type_name::into_string(type_name::get<T0>())), ascii::into_bytes(type_name::into_string(type_name::get<T1>())));
        assert!(!skyx_amm::comparator::is_equal(&result), ERR_IDENTICAL_TOKENS);
        skyx_amm::comparator::is_smaller_than(&result)
    }
    
    public fun left_amount<T>(reserve: &coin::Coin<T>, amount_out: u64) : u64 {
        assert!(reserve.value() >= amount_out, ERR_INSUFFICIENT_LIQUIDITY);
        reserve.value() - amount_out
    }
    
    public fun quote(amount_x: u64, reserve_x: u64, reserve_y: u64) : u64 {
        assert!(amount_x > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        ((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128)) as u64
    }
}

