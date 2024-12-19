module skyx_amm::comparator {
    use std::bcs;

    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

    public struct Result has drop {
        inner: u8,
    }

    public fun compare<T>(left: &T, right: &T): Result {
        compare_u8_vector(
            bcs::to_bytes<T>(left),
            bcs::to_bytes<T>(right)
        )
    }

    public fun compare_u8_vector(left: vector<u8>, right: vector<u8>): Result {
        let left_length = left.length<u8>();
        let right_length = right.length<u8>();
        let mut idx = 0;
        while (idx < left_length && idx < right_length) {
            let left_byte = *&left[idx];
            let right_byte = *&right[idx];
            if (left_byte < right_byte) {return Result {inner: SMALLER}};
            if (left_byte > right_byte) {return Result {inner: GREATER}};
            idx = idx + 1;
        };
        if (left_length < right_length) {
            Result {inner: SMALLER}
        } else {
            if (left_length > right_length) {
                Result {inner: GREATER}
            }
            else {
                Result {inner: EQUAL}
            }
        }
    }

    public fun is_equal(self: &Result): bool {
        self.inner == EQUAL
    }

    public fun is_smaller_than(self: &Result): bool {
        self.inner == SMALLER
    }

    public fun is_greater_than(self: &Result): bool {
        self.inner == GREATER
    }

    #[test]
    public fun test_strings() {
        use std::string;

        let value0 = string::utf8(b"alpha");
        let value1 = string::utf8(b"beta");
        let value2 = string::utf8(b"betaa");

        assert!(
            is_equal(&compare(&value0, &value0)),
            0
        );
        assert!(
            is_equal(&compare(&value1, &value1)),
            1
        );
        assert!(
            is_equal(&compare(&value2, &value2)),
            2
        );

        assert!(
            is_greater_than(&compare(&value0, &value1)),
            3
        );
        assert!(
            is_smaller_than(&compare(&value1, &value0)),
            4
        );

        assert!(
            is_smaller_than(&compare(&value0, &value2)),
            5
        );
        assert!(
            is_greater_than(&compare(&value2, &value0)),
            6
        );

        assert!(
            is_smaller_than(&compare(&value1, &value2)),
            7
        );
        assert!(
            is_greater_than(&compare(&value2, &value1)),
            8
        );
    }

    #[test]
    #[expected_failure]
    public fun test_integer() {
        // 1(0x1) will be larger than 256(0x100) after BCS serialization.
        let value0: u128 = 1;
        let value1: u128 = 256;

        assert!(
            is_equal(&compare(&value0, &value0)),
            0
        );
        assert!(
            is_equal(&compare(&value1, &value1)),
            1
        );

        assert!(
            is_smaller_than(&compare(&value0, &value1)),
            2
        );
        assert!(
            is_greater_than(&compare(&value1, &value0)),
            3
        );
    }

    #[test]
    public fun test_u128() {
        let value0: u128 = 5;
        let value1: u128 = 152;
        let value2: u128 = 511; // 0x1ff

        assert!(
            is_equal(&compare(&value0, &value0)),
            0
        );
        assert!(
            is_equal(&compare(&value1, &value1)),
            1
        );
        assert!(
            is_equal(&compare(&value2, &value2)),
            2
        );

        assert!(
            is_smaller_than(&compare(&value0, &value1)),
            2
        );
        assert!(
            is_greater_than(&compare(&value1, &value0)),
            3
        );

        assert!(
            is_smaller_than(&compare(&value0, &value2)),
            3
        );
        assert!(
            is_greater_than(&compare(&value2, &value0)),
            4
        );

        assert!(
            is_smaller_than(&compare(&value1, &value2)),
            5
        );
        assert!(
            is_greater_than(&compare(&value2, &value1)),
            6
        );
    }

    #[test_only]
    public struct Complex has drop {
        value0: vector<u128>,
        value1: u8,
        value2: u64,
    }

    #[test]
    public fun test_complex() {
        let mut value0_0 = vector::empty();
        vector::push_back(&mut value0_0, 10);
        vector::push_back(&mut value0_0, 9);
        vector::push_back(&mut value0_0, 5);

        let mut value0_1 = vector::empty();
        vector::push_back(&mut value0_1, 10);
        vector::push_back(&mut value0_1, 9);
        vector::push_back(&mut value0_1, 5);
        vector::push_back(&mut value0_1, 1);

        let base = Complex {
            value0: value0_0,
            value1: 13,
            value2: 41,
        };

        let other_0 = Complex {
            value0: value0_1,
            value1: 13,
            value2: 41,
        };

        let other_1 = Complex {
            value0: copy value0_0,
            value1: 14,
            value2: 41,
        };

        let other_2 = Complex {
            value0: value0_0,
            value1: 13,
            value2: 42,
        };

        assert!(is_equal(&compare(&base, &base)), 0);
        assert!(
            is_smaller_than(&compare(&base, &other_0)),
            1
        );
        assert!(
            is_greater_than(&compare(&other_0, &base)),
            2
        );
        assert!(
            is_smaller_than(&compare(&base, &other_1)),
            3
        );
        assert!(
            is_greater_than(&compare(&other_1, &base)),
            4
        );
        assert!(
            is_smaller_than(&compare(&base, &other_2)),
            5
        );
        assert!(
            is_greater_than(&compare(&other_2, &base)),
            6
        );
    }
}
