// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use aptos_gas_schedule::gas_params::natives::aptos_framework::*;
use aptos_native_interface::{
    safely_assert_eq, safely_pop_arg, RawSafeNative, SafeNativeBuilder, SafeNativeContext,
    SafeNativeError, SafeNativeResult,
};
use aptos_types::vm_status::sub_status::NFE_BCS_SERIALIZATION_FAILURE;
use move_vm_runtime::native_functions::NativeFunction;
use move_vm_types::{
    loaded_data::runtime_types::Type,
    values::{Reference, Value},
};
use smallvec::{smallvec, SmallVec};
use std::collections::VecDeque;

fn native_encode(
    context: &mut SafeNativeContext,
    ty_args: Vec<Type>,
    mut args: VecDeque<Value>,
) -> SafeNativeResult<SmallVec<[Value; 1]>> {
    safely_assert_eq!(ty_args.len(), 1);
    safely_assert_eq!(args.len(), 1);

    let v = safely_pop_arg!(args, Reference);

    context.charge(OBJECT_EXISTS_AT_BASE)?;

    let val = v.read_ref()?;
    Ok(smallvec![Value::vector_u8(val.rlp_encode())])
}

fn native_decode(
    context: &mut SafeNativeContext,
    mut ty_args: Vec<Type>,
    mut args: VecDeque<Value>,
) -> SafeNativeResult<SmallVec<[Value; 1]>> {
    safely_assert_eq!(ty_args.len(), 1);
    safely_assert_eq!(args.len(), 1);

    let val_type: Type = ty_args.pop().unwrap();
    let val = safely_pop_arg!(args, Reference);

    let val = val.read_ref()?;

    context.charge(OBJECT_EXISTS_AT_BASE)?;

    let mut buffer: Vec<u8> = vec![];
    match val.rlp_decode(&mut buffer) {
        Some(buffer) => buffer,
        None => {
            return Err(SafeNativeError::Abort {
                abort_code: NFE_BCS_SERIALIZATION_FAILURE,
            })
        },
    };

    Ok(smallvec![Value::vector_u8(buffer)])
}

/***************************************************************************************************
 * module
 *
 **************************************************************************************************/
pub fn make_all(
    builder: &SafeNativeBuilder,
) -> impl Iterator<Item = (String, NativeFunction)> + '_ {
    let natives = [
        ("encode", native_encode as RawSafeNative),
        ("decode", native_decode),
    ];

    builder.make_named_natives(natives)
}
