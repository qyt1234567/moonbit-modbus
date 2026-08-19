///|
/// Build a read-coils request (function 01).
pub fn read_coils(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  read_bits_request(unit_id, 1, address, quantity, 2000)
}

///|
/// Build a read-discrete-inputs request (function 02).
pub fn read_discrete_inputs(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  read_bits_request(unit_id, 2, address, quantity, 2000)
}

///|
fn read_bits_request(
  unit_id : Byte,
  function : Byte,
  address : UInt16,
  quantity : UInt16,
  limit : Int,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if quantity < 1 || quantity.to_int() > limit {
    return Err(InvalidQuantity)
  }
  if !valid_address_range(address, quantity.to_int()) {
    return Err(InvalidAddress)
  }
  Ok({
    unit_id,
    pdu: {
      function,
      data: address_bytes(address).add(quantity_bytes_checked(quantity)),
    },
  })
}

///|
/// Build a read-holding-registers request (function 03).
pub fn read_holding_registers(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  read_registers_request(unit_id, 3, address, quantity)
}

///|
/// Build a read-input-registers request (function 04).
pub fn read_input_registers(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  read_registers_request(unit_id, 4, address, quantity)
}

///|
fn read_registers_request(
  unit_id : Byte,
  function : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if quantity < 1 || quantity.to_int() > 125 {
    return Err(InvalidQuantity)
  }
  if !valid_address_range(address, quantity.to_int()) {
    return Err(InvalidAddress)
  }
  Ok({
    unit_id,
    pdu: {
      function,
      data: address_bytes(address).add(quantity_bytes_checked(quantity)),
    },
  })
}

///|
/// Build a write-single-coil request (function 05).
pub fn write_single_coil(
  unit_id : Byte,
  address : UInt16,
  value : Bool,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  let encoded : UInt16 = if value { 0xFF00 } else { 0 }
  Ok({
    unit_id,
    pdu: {
      function: 5,
      data: address_bytes(address).add(quantity_bytes_checked(encoded)),
    },
  })
}

///|
/// Build a write-single-register request (function 06) with validation.
pub fn write_single_register_checked(
  unit_id : Byte,
  address : UInt16,
  value : UInt16,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok(write_single_register(unit_id, address, value))
  }
}

///|
/// Pack boolean values into Modbus least-significant-bit-first bytes.
fn pack_coils_for_request(values : Array[Bool]) -> Array[Byte] {
  let out : Array[Byte] = []
  let byte_count = (values.length() + 7) / 8
  for _ in 0..<byte_count {
    out.push(0)
  }
  for i, value in values {
    if value {
      out[i / 8] = out[i / 8] | (1 << (i % 8)).to_byte()
    }
  }
  out
}

///|
fn append_bytes_to(out : Array[Byte], values : Array[Byte]) -> Unit {
  for value in values {
    out.push(value)
  }
}

///|
/// Build a write-multiple-coils request (function 15).
pub fn write_multiple_coils(
  unit_id : Byte,
  address : UInt16,
  values : Array[Bool],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if values.length() < 1 || values.length() > 1968 {
    return Err(InvalidQuantity)
  }
  if !valid_address_range(address, values.length()) {
    return Err(InvalidAddress)
  }
  let data : Array[Byte] = []
  append_bytes_to(data, address_bytes(address))
  append_bytes_to(data, quantity_bytes_checked(values.length().to_uint16()))
  data.push(((values.length() + 7) / 8).to_byte())
  append_bytes_to(data, pack_coils_for_request(values))
  Ok({ unit_id, pdu: { function: 15, data } })
}

///|
/// Build a write-multiple-registers request (function 16).
pub fn write_multiple_registers(
  unit_id : Byte,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if values.length() < 1 || values.length() > 123 {
    return Err(InvalidQuantity)
  }
  if !valid_address_range(address, values.length()) {
    return Err(InvalidAddress)
  }
  let data : Array[Byte] = []
  append_bytes_to(data, address_bytes(address))
  append_bytes_to(data, quantity_bytes_checked(values.length().to_uint16()))
  data.push((values.length() * 2).to_byte())
  for value in values {
    append_bytes_to(data, quantity_bytes_checked(value))
  }
  Ok({ unit_id, pdu: { function: 16, data } })
}

///|
/// Build a mask-write-register request (function 22).
pub fn mask_write_register(
  unit_id : Byte,
  address : UInt16,
  and_mask : UInt16,
  or_mask : UInt16,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  let data : Array[Byte] = []
  append_bytes_to(data, address_bytes(address))
  append_bytes_to(data, quantity_bytes_checked(and_mask))
  append_bytes_to(data, quantity_bytes_checked(or_mask))
  Ok({ unit_id, pdu: { function: 22, data } })
}

///|
/// Build a combined read/write-multiple-registers request (function 23).
pub fn read_write_multiple_registers(
  unit_id : Byte,
  read_address : UInt16,
  read_quantity : UInt16,
  write_address : UInt16,
  write_values : Array[UInt16],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if read_quantity < 1 || read_quantity > 125 {
    return Err(InvalidQuantity)
  }
  if write_values.length() < 1 || write_values.length() > 121 {
    return Err(InvalidQuantity)
  }
  if !valid_address_range(read_address, read_quantity.to_int()) ||
    !valid_address_range(write_address, write_values.length()) {
    return Err(InvalidAddress)
  }
  let data : Array[Byte] = []
  append_bytes_to(data, address_bytes(read_address))
  append_bytes_to(data, quantity_bytes_checked(read_quantity))
  append_bytes_to(data, address_bytes(write_address))
  append_bytes_to(
    data,
    quantity_bytes_checked(write_values.length().to_uint16()),
  )
  data.push((write_values.length() * 2).to_byte())
  for value in write_values {
    append_bytes_to(data, quantity_bytes_checked(value))
  }
  Ok({ unit_id, pdu: { function: 23, data } })
}

///|
/// Build a diagnostics request (function 08).
pub fn diagnostics(
  unit_id : Byte,
  subfunction : UInt16,
  data : Array[Byte],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if data.length() % 2 != 0 {
    return Err(InvalidLength)
  }
  let payload : Array[Byte] = []
  append_bytes_to(payload, quantity_bytes_checked(subfunction))
  append_bytes_to(payload, data)
  Ok({ unit_id, pdu: { function: 8, data: payload } })
}

///|
/// Build the common Return Query Data diagnostics request.
pub fn diagnostics_return_query_data(
  unit_id : Byte,
  data : Array[Byte],
) -> Result[Frame, ModbusError] {
  diagnostics(unit_id, 0, data)
}

///|
/// Build a request for the exception status byte (function 07).
pub fn read_exception_status(unit_id : Byte) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({ unit_id, pdu: { function: 7, data: [] } })
  }
}

///|
/// Build a request for the communication event counter (function 11).
pub fn get_comm_event_counter(unit_id : Byte) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({ unit_id, pdu: { function: 11, data: [] } })
  }
}

///|
/// Build a request for the communication event log (function 12).
pub fn get_comm_event_log(unit_id : Byte) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({ unit_id, pdu: { function: 12, data: [] } })
  }
}

///|
/// Build a Report Server ID request (function 17).
pub fn report_server_id(unit_id : Byte) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({ unit_id, pdu: { function: 17, data: [] } })
  }
}

///|
/// Build a Read FIFO Queue request (function 24).
pub fn read_fifo_queue(
  unit_id : Byte,
  address : UInt16,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({ unit_id, pdu: { function: 24, data: address_bytes(address) } })
  }
}

///|
/// Build a generic encapsulated-interface request (function 43).
pub fn encapsulated_interface(
  unit_id : Byte,
  mei_type : Byte,
  payload : Array[Byte],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  Ok({ unit_id, pdu: { function: 43, data: [mei_type].add(payload) } })
}

///|
/// Build a standard Modbus exception response.
pub fn exception_response(
  unit_id : Byte,
  function : Byte,
  code : Byte,
) -> Frame {
  { unit_id, pdu: { function: function | 0x80, data: [code] } }
}

///|
/// Build a typed exception response.
pub fn typed_exception_response(
  unit_id : Byte,
  function : Byte,
  code : ExceptionCode,
) -> Frame {
  exception_response(unit_id, function, code.to_byte())
}

///|
/// Whether a PDU is an exception response.
pub fn is_exception(frame : Frame) -> Bool {
  frame.pdu.is_exception()
}

///|
/// Return the function number without the exception bit.
pub fn base_function(frame : Frame) -> Byte {
  frame.pdu.function & 0x7F
}

///|
/// Construct a response with an explicit function and owned data array.
pub fn response_frame(request : Frame, data : Array[Byte]) -> Frame {
  { unit_id: request.unit_id, pdu: { function: request.pdu.function, data } }
}

///|
/// Construct an exception from a protocol error.
pub fn error_response(request : Frame, error : ModbusError) -> Frame {
  let code = match error {
    InvalidFunction | Unsupported => IllegalFunction
    InvalidAddress | UnitMismatch => IllegalDataAddress
    InvalidQuantity | InvalidByteCount | InvalidData | InvalidLength =>
      IllegalDataValue
    Busy => ServerDeviceBusy
    _ => ServerDeviceFailure
  }
  typed_exception_response(request.unit_id, request.pdu.function, code)
}

///|
/// Return a copy of a frame with a different unit identifier.
pub fn with_unit(frame : Frame, unit_id : Byte) -> Frame {
  { ..frame, unit_id, }
}

///|
/// Return a copy of a frame with a different function code.
pub fn with_function(frame : Frame, function : Byte) -> Frame {
  { ..frame, pdu: { ..frame.pdu, function, } }
}

///|
/// Return a copy of a frame with a different data payload.
pub fn with_data(frame : Frame, data : Array[Byte]) -> Frame {
  { ..frame, pdu: { ..frame.pdu, data, } }
}
