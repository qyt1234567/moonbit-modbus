///|
/// Read a big-endian unsigned 16-bit value from a byte array.
pub fn read_u16_be(
  bytes : Array[Byte],
  offset : Int,
) -> Result[UInt16, ModbusError] {
  if offset < 0 || offset + 2 > bytes.length() {
    Err(Incomplete)
  } else {
    Ok(bytes[offset].to_uint16().shl(8) + bytes[offset + 1].to_uint16())
  }
}

///|
/// Read a big-endian unsigned 32-bit value using MoonBit's platform unsigned type.
pub fn read_u32_be(
  bytes : Array[Byte],
  offset : Int,
) -> Result[UInt, ModbusError] {
  if offset < 0 || offset + 4 > bytes.length() {
    return Err(Incomplete)
  }
  Ok(
    (bytes[offset].to_uint() << 24) |
    (bytes[offset + 1].to_uint() << 16) |
    (bytes[offset + 2].to_uint() << 8) |
    bytes[offset + 3].to_uint(),
  )
}

///|
/// Append a big-endian unsigned 16-bit value.
pub fn append_u16_be(out : Array[Byte], value : UInt16) -> Unit {
  out.push(value.shr(8).to_byte())
  out.push(value.to_byte())
}

///|
/// Append a big-endian unsigned 32-bit value.
pub fn append_u32_be(out : Array[Byte], value : UInt) -> Unit {
  out.push((value >> 24).to_byte())
  out.push((value >> 16).to_byte())
  out.push((value >> 8).to_byte())
  out.push(value.to_byte())
}

///|
/// Make an owned byte-array copy. Protocol parsers use this to avoid retaining views.
pub fn copy_bytes(bytes : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  for byte in bytes {
    out.push(byte)
  }
  out
}

///|
/// Copy a half-open range and return a protocol error when the range is invalid.
pub fn copy_range(
  bytes : Array[Byte],
  start : Int,
  end : Int,
) -> Result[Array[Byte], ModbusError] {
  if start < 0 || end < start || end > bytes.length() {
    return Err(InvalidLength)
  }
  let out : Array[Byte] = []
  for i in start..<end {
    out.push(bytes[i])
  }
  Ok(out)
}

///|
/// Check whether an address/count pair fits in the 16-bit Modbus address space.
pub fn valid_address_range(address : UInt16, quantity : Int) -> Bool {
  quantity > 0 && address.to_int() + quantity <= 65536
}

///|
/// Validate a unit identifier for a request.
pub fn validate_unit(
  unit_id : Byte,
  allow_broadcast : Bool,
) -> Result[Unit, ModbusError] {
  if is_valid_unit_id(unit_id, broadcast=allow_broadcast) {
    Ok(())
  } else {
    Err(InvalidUnitId)
  }
}

///|
/// Return the ordinary function code for an exception response.
pub fn ordinary_function(function : Byte) -> Byte {
  function & 0x7F
}

///|
/// Check that a function code is in the supported public subset.
pub fn supported_function(function : Byte) -> Bool {
  match function_code(function) {
    Unknown(_) => false
    _ => true
  }
}

///|
/// Validate a request PDU's byte-level shape and protocol limits.
pub fn validate_pdu(pdu : Pdu) -> Result[Unit, ModbusError] {
  if pdu.function == 0 || pdu.is_exception() {
    return Err(InvalidFunction)
  }
  let size = pdu.data.length()
  match function_code(pdu.function) {
    ReadCoils
    | ReadDiscreteInputs
    | ReadHoldingRegisters
    | ReadInputRegisters =>
      if size != 4 {
        Err(InvalidLength)
      } else {
        let quantity = pdu.data[2].to_uint16().shl(8) + pdu.data[3].to_uint16()
        let limit = if pdu.function == 3 || pdu.function == 4 {
          125
        } else {
          2000
        }
        if quantity < 1 || quantity.to_int() > limit {
          Err(InvalidQuantity)
        } else if !valid_address_range(
            pdu.data[0].to_uint16().shl(8) + pdu.data[1].to_uint16(),
            quantity.to_int(),
          ) {
          Err(InvalidAddress)
        } else {
          Ok(())
        }
      }
    WriteSingleCoil | WriteSingleRegister =>
      if size != 4 {
        Err(InvalidLength)
      } else if pdu.function == 5 &&
        pdu.data[2].to_uint16().shl(8) + pdu.data[3].to_uint16() != 0 &&
        pdu.data[2].to_uint16().shl(8) + pdu.data[3].to_uint16() != 0xFF00 {
        Err(InvalidData)
      } else {
        Ok(())
      }
    WriteMultipleCoils => validate_write_multiple_coils(pdu.data)
    WriteMultipleRegisters => validate_write_multiple_registers(pdu.data)
    MaskWriteRegister => if size == 6 { Ok(()) } else { Err(InvalidLength) }
    ReadWriteMultipleRegisters => validate_read_write_multiple(pdu.data)
    ReadExceptionStatus => if size == 0 { Ok(()) } else { Err(InvalidLength) }
    Diagnostics =>
      if size >= 2 && size % 2 == 0 {
        Ok(())
      } else {
        Err(InvalidLength)
      }
    GetCommEventCounter => if size == 0 { Ok(()) } else { Err(InvalidLength) }
    GetCommEventLog => if size == 0 { Ok(()) } else { Err(InvalidLength) }
    ReportServerId => if size == 0 { Ok(()) } else { Err(InvalidLength) }
    ReadFifoQueue => if size == 2 { Ok(()) } else { Err(InvalidLength) }
    EncapsulatedInterface => if size >= 1 { Ok(()) } else { Err(InvalidLength) }
    ReadFileRecord => if size >= 1 { Ok(()) } else { Err(InvalidLength) }
    WriteFileRecord => if size >= 1 { Ok(()) } else { Err(InvalidLength) }
    ReportServerIdExtended => Ok(())
    Unknown(_) => Err(Unsupported)
  }
}

///|
fn validate_write_multiple_coils(
  data : Array[Byte],
) -> Result[Unit, ModbusError] {
  if data.length() < 6 {
    return Err(InvalidLength)
  }
  let quantity = data[2].to_uint16().shl(8) + data[3].to_uint16()
  let byte_count = data[4].to_int()
  if quantity < 1 || quantity > 1968 {
    Err(InvalidQuantity)
  } else if !valid_address_range(
      data[0].to_uint16().shl(8) + data[1].to_uint16(),
      quantity.to_int(),
    ) {
    Err(InvalidAddress)
  } else if byte_count != (quantity.to_int() + 7) / 8 {
    Err(InvalidByteCount)
  } else if data.length() != 5 + byte_count {
    Err(InvalidLength)
  } else {
    Ok(())
  }
}

///|
fn validate_write_multiple_registers(
  data : Array[Byte],
) -> Result[Unit, ModbusError] {
  if data.length() < 6 {
    return Err(InvalidLength)
  }
  let quantity = data[2].to_uint16().shl(8) + data[3].to_uint16()
  let byte_count = data[4].to_int()
  if quantity < 1 || quantity > 123 {
    Err(InvalidQuantity)
  } else if !valid_address_range(
      data[0].to_uint16().shl(8) + data[1].to_uint16(),
      quantity.to_int(),
    ) {
    Err(InvalidAddress)
  } else if byte_count != quantity.to_int() * 2 {
    Err(InvalidByteCount)
  } else if data.length() != 5 + byte_count {
    Err(InvalidLength)
  } else {
    Ok(())
  }
}

///|
fn validate_read_write_multiple(
  data : Array[Byte],
) -> Result[Unit, ModbusError] {
  if data.length() != 9 {
    return Err(InvalidLength)
  }
  let read_quantity = data[2].to_uint16().shl(8) + data[3].to_uint16()
  let write_quantity = data[6].to_uint16().shl(8) + data[7].to_uint16()
  if read_quantity < 1 ||
    read_quantity > 125 ||
    write_quantity < 1 ||
    write_quantity > 121 {
    Err(InvalidQuantity)
  } else if !valid_address_range(
      data[0].to_uint16().shl(8) + data[1].to_uint16(),
      read_quantity.to_int(),
    ) ||
    !valid_address_range(
      data[4].to_uint16().shl(8) + data[5].to_uint16(),
      write_quantity.to_int(),
    ) {
    Err(InvalidAddress)
  } else {
    Ok(())
  }
}

///|
/// Validate a complete logical frame before encoding it on any transport.
pub fn validate_frame(
  frame : Frame,
  allow_broadcast : Bool,
) -> Result[Unit, ModbusError] {
  match validate_unit(frame.unit_id, allow_broadcast) {
    Ok(_) => validate_pdu(frame.pdu)
    Err(error) => Err(error)
  }
}

///|
/// Validate a frame for wire encoding without assuming request-only payload shapes.
pub fn validate_wire_frame(
  frame : Frame,
  allow_broadcast : Bool,
) -> Result[Unit, ModbusError] {
  match validate_unit(frame.unit_id, allow_broadcast) {
    Err(error) => Err(error)
    Ok(_) =>
      if frame.pdu.function == 0 || frame.pdu.data.length() > 253 {
        Err(InvalidLength)
      } else {
        Ok(())
      }
  }
}

///|
/// Return the expected response function byte for a request.
pub fn expected_response_function(request : Frame) -> Byte {
  request.pdu.function
}

///|
/// Validate the common unit/function relationship of a response.
pub fn validate_response_header(
  request : Frame,
  response : Frame,
) -> Result[Unit, ModbusError] {
  if request.unit_id != response.unit_id {
    return Err(UnitMismatch)
  }
  if response.pdu.function == (request.pdu.function | 0x80) {
    if response.pdu.data.length() == 1 {
      Ok(())
    } else {
      Err(InvalidLength)
    }
  } else if response.pdu.function != expected_response_function(request) {
    Err(InvalidFunction)
  } else {
    Ok(())
  }
}

///|
/// Human-readable function-code name used by diagnostic output.
pub fn function_name(function : Byte) -> String {
  match function_code(ordinary_function(function)) {
    ReadCoils => "read-coils"
    ReadDiscreteInputs => "read-discrete-inputs"
    ReadHoldingRegisters => "read-holding-registers"
    ReadInputRegisters => "read-input-registers"
    WriteSingleCoil => "write-single-coil"
    WriteSingleRegister => "write-single-register"
    ReadExceptionStatus => "read-exception-status"
    Diagnostics => "diagnostics"
    GetCommEventCounter => "get-comm-event-counter"
    GetCommEventLog => "get-comm-event-log"
    ReportServerId | ReportServerIdExtended => "report-server-id"
    WriteMultipleCoils => "write-multiple-coils"
    WriteMultipleRegisters => "write-multiple-registers"
    ReadFileRecord => "read-file-record"
    WriteFileRecord => "write-file-record"
    MaskWriteRegister => "mask-write-register"
    ReadWriteMultipleRegisters => "read-write-multiple-registers"
    ReadFifoQueue => "read-fifo-queue"
    EncapsulatedInterface => "encapsulated-interface"
    Unknown(_) => "unknown"
  }
}

///|
/// Return the maximum legal request quantity for a read function.
pub fn read_quantity_limit(function : Byte) -> Int {
  if function == 1 || function == 2 {
    2000
  } else if function == 3 || function == 4 {
    125
  } else {
    0
  }
}

///|
/// Return the maximum legal write quantity for a write-multiple function.
pub fn write_quantity_limit(function : Byte) -> Int {
  if function == 15 {
    1968
  } else if function == 16 {
    123
  } else {
    0
  }
}

///|
/// Make the two-byte address representation used by request builders.
pub fn address_bytes(address : UInt16) -> Array[Byte] {
  [address.shr(8).to_byte(), address.to_byte()]
}

///|
/// Make a quantity representation used by request builders.
pub fn quantity_bytes_checked(quantity : UInt16) -> Array[Byte] {
  [quantity.shr(8).to_byte(), quantity.to_byte()]
}
