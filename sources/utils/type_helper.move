module skyx_amm::type_helper {
    use std::string::{ String, from_ascii };
    use std::type_name::{ get, into_string };

    public fun get_type_name<T>(): String {
        from_ascii(
            into_string(get<T>())
        )
    }
}
