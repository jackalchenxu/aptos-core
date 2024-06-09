/// RLP (Recursive Length Prefix) Recursive Length Prefix encoding is the most commonly used serialization format method in Ethereum.
/// https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/
///
/// RLP encoding function takes in an item, an item is:
/// - a string(byte array)                --> encode_byte_array()
/// - list of items([item1, item2, ...])  --> encode_list()
/// - a positive integer                  --> encode_integer()
module aptos_std::rlp {
    use std::bcs;
    use std::vector;

    const E_INVALID_RLP_DATA: u64 = 1;
    const E_DATA_TOO_SHORT: u64 = 2;

    /// RLP list encode implementation, eg: [item1_bytes, item2_bytes]
    public fun encode_list(data: &vector<vector<u8>>): vector<u8> {
        let rlp_items = vector::empty<u8>();
        let list_len = vector::length(data);
        let i = 0;
        while (i < list_len) {
            let item = vector::borrow(data, i);
            vector::append<u8>(&mut rlp_items, *item);
            i = i + 1;
        };

        let output = vector::empty<u8>();

        let rlp_len = vector::length(&rlp_items);
        if (rlp_len < 56) {
            vector::push_back<u8>(&mut output, (rlp_len as u8) + 0xc0);
            vector::append<u8>(&mut output, rlp_items);
        } else {
            let length_BE = encode_len(rlp_len);
            let length_BE_len = vector::length(&length_BE);
            vector::push_back<u8>(&mut output, (length_BE_len as u8) + 0xf7);
            vector::append<u8>(&mut output, length_BE);
            vector::append<u8>(&mut output, rlp_items);
        };

        output
    }

    /// Encode single item, encode multi-bytes length
    /// Follow BigEndian format
    public fun encode_len<T: drop>(len: T): vector<u8> {
        let bytes: vector<u8> = bcs::to_bytes(&len);
        let bytes_len = (vector::length(&bytes) as u8);

        let output = vector::empty<u8>();
        vector::push_back<u8>(&mut output, 0x80 + bytes_len);
        vector::append<u8>(&mut output, bytes);
        output
    }

    /// Byte_array RLP encode implementation
    public fun encode(data: &vector<u8>): vector<u8> {
        let rlp = vector::empty<u8>();
        let data_len = vector::length(data);

        // single byte if data is in [0, 0x7f], keep the same   
        if (data_len == 1 && *vector::borrow(data, 0) < 0x80) {
            vector::append<u8>(&mut rlp, *data);
        } else if (data_len < 56) {
            // multi bytes, if length in [2, 55]
            // (0x80 + length) | bytes
            vector::push_back<u8>(&mut rlp, (data_len as u8) + 0x80);
            vector::append<u8>(&mut rlp, *data);
        } else {
            // (multi bytes if length > 0x7f) or (single byte but data in [0x80, 0xFF])
            // (0xb7 + byte_length(encode(length))) | encode(length) | bytes
            let length_BE = encode_len(data_len);
            let length_BE_len = vector::length(&length_BE);
            vector::push_back<u8>(&mut rlp, (length_BE_len as u8) + 0xb7);
            vector::append<u8>(&mut rlp, length_BE);
            vector::append<u8>(&mut rlp, *data);
        };

        rlp
    }

    /// byte inception:
    /// 0x00 - 0x7f => Direct translation of the character according to ASCII
    /// 0x81        => immediately followed by a special character
    /// 0x82 - 0xb7 => immediately followed by a string no larger than 55
    /// 0xb8 - 0xbf => immediately followed by a string larger than 55
    /// 0xc1 - 0xf7 => immediately followed by an array of no more than 55 characters
    /// 0xf8 - 0xff => immediately followed by an array of more than 55 characters
    fun decode(
        data: &vector<u8>,
        offset: u64
    ): (vector<vector<u8>>, u64) {
        let data_len = vector::length(data);
        assert!(offset < data_len, E_DATA_TOO_SHORT);

        let first_byte = *vector::borrow(data, offset);
        if (first_byte >= 0xf8) {
            let length_of_length = ((first_byte - 247u8) as u64);
            assert!(offset + length_of_length < data_len, E_DATA_TOO_SHORT);
            let length = unarrayify_integer(data, offset + 1, (length_of_length as u8));
            assert!(offset + length_of_length + length < data_len, E_DATA_TOO_SHORT);
            decode_children(data, offset, offset + 1 + length_of_length, length_of_length + length)
        } else if (first_byte >= 0xc0) {
            let length = ((first_byte - 192u8) as u64);
            assert!(offset + length < data_len, E_DATA_TOO_SHORT);
            decode_children(data, offset, offset + 1, length)
        } else if (first_byte >= 0xb8) {
            let length_of_length = ((first_byte - 183u8) as u64);
            assert!(offset + length_of_length < data_len, E_DATA_TOO_SHORT);
            let length = unarrayify_integer(data, offset + 1, (length_of_length as u8));
            assert!(offset + length_of_length + length < data_len, E_DATA_TOO_SHORT);

            let bytes = vector::slice(data, offset + 1 + length_of_length, offset + 1 + length_of_length + length);
            (vector::singleton(bytes), 1 + length_of_length + length)
        } else if (first_byte >= 128u8) {
            // 0x80
            let length = ((first_byte - 128u8) as u64);
            assert!(offset + length < data_len, E_DATA_TOO_SHORT);
            let bytes = vector::slice(data, offset + 1, offset + 1 + length);
            (vector::singleton(bytes), 1 + length)
        } else {
            let bytes = vector::slice(data, offset, offset + 1);
            (vector::singleton(bytes), 1)
        }
    }

    fun decode_children(
        data: &vector<u8>,
        offset: u64,
        child_offset: u64,
        length: u64
    ): (vector<vector<u8>>, u64) {
        let result = vector::empty();

        while (child_offset < offset + 1 + length) {
            let (decoded, consumed) = decode(data, child_offset);
            vector::append(&mut result, decoded);
            child_offset = child_offset + consumed;
            assert!(child_offset <= offset + 1 + length, E_DATA_TOO_SHORT);
        };
        (result, 1 + length)
    }


    /// RLP multi items(list) decode implementation
    /// Nested arrays are not supported.
    public fun decode_list(data: &vector<u8>): vector<vector<u8>> {
        let (decoded, consumed) = decode(data, 0);
        assert!(consumed == vector::length(data), E_INVALID_RLP_DATA);
        decoded
    }

    fun unarrayify_integer(
        data: &vector<u8>,
        offset: u64,
        length: u8
    ): u64 {
        let result = 0;
        let i = 0u8;
        while (i < length) {
            result = result * 256 + (*vector::borrow(data, offset + (i as u64)) as u64);
            i = i + 1;
        };
        result
    }

    //
    // Testing
    //
    #[test]
    fun test_rlp_encode() {
        // []
        let input = vector::empty<vector<u8>>();
        let rlp = encode_list(&input);
        assert!((*vector::borrow<u8>(&rlp, 0) as u8) == 0xc0, 0);

        // [0x01]
        let input = vector::empty<vector<u8>>();
        let items = vector::empty<u8>();
        vector::push_back(&mut items, 0x1_u8);

        vector::push_back(&mut input, encode(&items));
        let rlp = encode_list(&input);
        assert!(vector::length(&rlp) == 2, 0);
        assert!((*vector::borrow<u8>(&rlp, 0) as u8) == 0xc1, 0);
        assert!((*vector::borrow<u8>(&rlp, 1) as u8) == 0x1, 0);

        // [0x01, 0x02]
        let input = vector::empty<vector<u8>>();
        let items = vector::empty<u8>();
        vector::push_back(&mut items, 0x1);
        vector::push_back(&mut items, 0x2);
        vector::push_back(&mut input, items);
        let rlp = encode_list(&input);
        assert!((*vector::borrow<u8>(&rlp, 0) as u8) == 0xc2, 0);
        assert!((*vector::borrow<u8>(&rlp, 1) as u8) == 0x01, 0);
        assert!((*vector::borrow<u8>(&rlp, 2) as u8) == 0x02, 0);

        // [0xFFCCB5, 0xFFC0B5]
        let input = vector::empty<vector<u8>>();
        let item_1 = vector::empty<u8>();
        vector::push_back(&mut item_1, 0xFF);
        vector::push_back(&mut item_1, 0xCC);
        vector::push_back(&mut item_1, 0xB5);

        let item_2 = vector::empty<u8>();
        vector::push_back(&mut item_2, 0xFF);
        vector::push_back(&mut item_2, 0xC0);
        vector::push_back(&mut item_2, 0xB5);

        vector::push_back(&mut input, encode(&item_1));
        vector::push_back(&mut input, encode(&item_2));
        let rlp = encode_list(&input);
        assert!((*vector::borrow<u8>(&rlp, 0) as u8) == 0xc8, 0);
        assert!((*vector::borrow<u8>(&rlp, 1) as u8) == 0x83, 1);
        assert!((*vector::borrow<u8>(&rlp, 2) as u8) == 0xff, 2);
        assert!((*vector::borrow<u8>(&rlp, 3) as u8) == 0xcc, 3);
        assert!((*vector::borrow<u8>(&rlp, 4) as u8) == 0xb5, 4);
        assert!((*vector::borrow<u8>(&rlp, 5) as u8) == 0x83, 5);
        assert!((*vector::borrow<u8>(&rlp, 6) as u8) == 0xff, 6);
        assert!((*vector::borrow<u8>(&rlp, 7) as u8) == 0xc0, 7);
        assert!((*vector::borrow<u8>(&rlp, 8) as u8) == 0xb5, 8);
    }
}