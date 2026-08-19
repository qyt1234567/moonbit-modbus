///|
/// Return whether an error is recoverable by a retry policy.
pub fn is_retryable(error : ModbusError) -> Bool {
  match error {
    Incomplete | InvalidChecksum | InvalidMbap | Busy | NoResponse => true
    _ => false
  }
}

///|
pub fn is_client_input_error(error : ModbusError) -> Bool {
  match error {
    InvalidUnitId
    | InvalidFunction
    | InvalidAddress
    | InvalidQuantity
    | InvalidByteCount
    | InvalidData
    | InvalidLength => true
    _ => false
  }
}

///|
pub fn is_transport_error(error : ModbusError) -> Bool {
  match error {
    Incomplete
    | InvalidChecksum
    | InvalidAscii
    | InvalidMbap
    | InvalidTransaction
    | NoResponse => true
    _ => false
  }
}

///|
pub fn exception_for_error(error : ModbusError) -> ExceptionCode {
  match error {
    InvalidFunction | Unsupported => IllegalFunction
    InvalidAddress | UnitMismatch => IllegalDataAddress
    InvalidQuantity | InvalidByteCount | InvalidData | InvalidLength =>
      IllegalDataValue
    Busy => ServerDeviceBusy
    _ => ServerDeviceFailure
  }
}

///|
pub fn safe_quantity(value : UInt16, limit : Int) -> Result[Int, ModbusError] {
  if limit < 1 || value.to_int() < 1 || value.to_int() > limit {
    Err(InvalidQuantity)
  } else {
    Ok(value.to_int())
  }
}

///|
pub fn safe_address(
  value : UInt16,
  quantity : Int,
) -> Result[Unit, ModbusError] {
  if valid_address_range(value, quantity) {
    Ok(())
  } else {
    Err(InvalidAddress)
  }
}

///|
pub fn bytes_equal(left : Array[Byte], right : Array[Byte]) -> Bool {
  left == right
}

///|
pub fn byte_sum(bytes : Array[Byte]) -> Byte {
  let mut sum : Byte = 0
  for byte in bytes {
    sum += byte
  }
  sum
}

///|
pub fn byte_xor(bytes : Array[Byte]) -> Byte {
  let mut value : Byte = 0
  for byte in bytes {
    value = value ^ byte
  }
  value
}

///|
pub fn clamp_int(
  value : Int,
  minimum : Int,
  maximum : Int,
) -> Result[Int, ModbusError] {
  if minimum > maximum {
    Err(InvalidData)
  } else if value < minimum {
    Ok(minimum)
  } else if value > maximum {
    Ok(maximum)
  } else {
    Ok(value)
  }
}
