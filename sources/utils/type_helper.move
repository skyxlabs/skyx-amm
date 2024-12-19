module skyx_amm::type_helper {
    use std::string;
    use std::type_name;

    public fun get_type_name<T>(): string::String {
        string::from_ascii(
            type_name::into_string(type_name::get<T>())
        )
    }
}
