module skyx_amm::treasury {
    public struct Treasury has store {
        treasurer: address,
    }

    public fun appoint(
        treasury: &mut Treasury,
        treasurer: address
    ) {
        treasury.treasurer = treasurer;
    }

    public(package) fun new(treasurer: address): Treasury {
        Treasury {treasurer: treasurer}
    }

    public fun treasurer(treasury: &Treasury): address {
        treasury.treasurer
    }
}
