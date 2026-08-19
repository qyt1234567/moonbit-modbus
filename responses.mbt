///|
/// Validate that a response is a normal response for a request.
fn expect_normal(
  request : Frame,
  response : Frame,
) -> Result[Unit, ModbusError] {
  match validate_response_header(request, response) {
    Err(error) => Err(error)
    Ok(_) => if response.is_exception() { Err(InvalidData) } else { Ok(()) }
  }
}

///|
/// Decode the exception code from a standard exception response.
pub fn exception_from_frame(
  frame : Frame,
) -> Result[ExceptionCode, ModbusError] {
  if !frame.is_exception() || frame.pdu.data.length() != 1 {
    Err(InvalidData)
  } else {
    Ok(exception_code(frame.pdu.data[0]))
  }
}

///|
/// Decode any response while preserving exception information.
pub fn decode_response(
  request : Frame,
  response : Frame,
) -> Result[ResponseValue, ModbusError] {
  match validate_response_header(request, response) {
    Err(error) => Err(error)
    Ok(_) => Ok(response_value(response))
  }
}

///|
/// Decode a read-coils or read-discrete-inputs response.
pub fn decode_bits_response(
  request : Frame,
  response : Frame,
) -> Result[Array[Bool], ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 1 {
    return Err(Incomplete)
  }
  let byte_count = response.pdu.data[0].to_int()
  if response.pdu.data.length() != byte_count + 1 {
    return Err(InvalidByteCount)
  }
  let requested = request.pdu.data[2].to_uint16().shl(8) +
    request.pdu.data[3].to_uint16()
  let expected = (requested.to_int() + 7) / 8
  if byte_count != expected {
    return Err(InvalidByteCount)
  }
  let bytes : Array[Byte] = []
  for index in 0..<byte_count {
    bytes.push(response.pdu.data[index + 1])
  }
  unpack_bits(bytes, requested.to_int())
}

///|
/// Decode a function 03 or 04 register response.
pub fn decode_register_response(
  request : Frame,
  response : Frame,
) -> Result[Array[UInt16], ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 1 {
    return Err(Incomplete)
  }
  let byte_count = response.pdu.data[0].to_int()
  let requested = request.pdu.data[2].to_uint16().shl(8) +
    request.pdu.data[3].to_uint16()
  if byte_count != requested.to_int() * 2 ||
    response.pdu.data.length() != byte_count + 1 {
    return Err(InvalidByteCount)
  }
  let payload : Array[Byte] = []
  for index in 0..<byte_count {
    payload.push(response.pdu.data[index + 1])
  }
  bytes_to_registers(payload, BigEndian)
}

///|
/// Decode a single-coil echo and return its logical value.
pub fn decode_write_single_coil(
  request : Frame,
  response : Frame,
) -> Result[Bool, ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 4 || response.pdu.data != request.pdu.data {
    return Err(InvalidData)
  }
  Ok(response.pdu.data[2] == 0xFF && response.pdu.data[3] == 0)
}

///|
/// Decode a single-register write echo.
pub fn decode_write_single_register(
  request : Frame,
  response : Frame,
) -> Result[UInt16, ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 4 || response.pdu.data != request.pdu.data {
    return Err(InvalidData)
  }
  Ok((response.pdu.data[2].to_uint16() << 8) | response.pdu.data[3].to_uint16())
}

///|
/// Decode a multiple-write echo and return `(address, quantity)`.
pub fn decode_multiple_write(
  request : Frame,
  response : Frame,
) -> Result[(UInt16, UInt16), ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 4 {
    return Err(InvalidLength)
  }
  if response.pdu.data[0] != request.pdu.data[0] ||
    response.pdu.data[1] != request.pdu.data[1] ||
    response.pdu.data[2] != request.pdu.data[2] ||
    response.pdu.data[3] != request.pdu.data[3] {
    return Err(InvalidData)
  }
  Ok(
    (
      (response.pdu.data[0].to_uint16() << 8) | response.pdu.data[1].to_uint16(),
      (response.pdu.data[2].to_uint16() << 8) | response.pdu.data[3].to_uint16(),
    ),
  )
}

///|
/// Decode a mask-write response and return `(and_mask, or_mask)`.
pub fn decode_mask_write(
  request : Frame,
  response : Frame,
) -> Result[(UInt16, UInt16), ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 6 || response.pdu.data != request.pdu.data {
    return Err(InvalidData)
  }
  Ok(
    (
      (response.pdu.data[2].to_uint16() << 8) | response.pdu.data[3].to_uint16(),
      (response.pdu.data[4].to_uint16() << 8) | response.pdu.data[5].to_uint16(),
    ),
  )
}

///|
/// Decode the register payload of a combined read/write response.
pub fn decode_read_write_response(
  request : Frame,
  response : Frame,
) -> Result[Array[UInt16], ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 1 {
    return Err(Incomplete)
  }
  let byte_count = response.pdu.data[0].to_int()
  let requested = request.pdu.data[2].to_uint16().shl(8) +
    request.pdu.data[3].to_uint16()
  if byte_count != requested.to_int() * 2 ||
    response.pdu.data.length() != byte_count + 1 {
    return Err(InvalidByteCount)
  }
  let payload : Array[Byte] = []
  for index in 0..<byte_count {
    payload.push(response.pdu.data[index + 1])
  }
  bytes_to_registers(payload, BigEndian)
}

///|
/// Decode the two-byte diagnostics subfunction and its data.
pub fn decode_diagnostics(
  request : Frame,
  response : Frame,
) -> Result[(UInt16, Array[Byte]), ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 2 || response.pdu.data.length() % 2 != 0 {
    return Err(InvalidLength)
  }
  let subfunction = (response.pdu.data[0].to_uint16() << 8) |
    response.pdu.data[1].to_uint16()
  let payload : Array[Byte] = []
  for index in 2..<response.pdu.data.length() {
    payload.push(response.pdu.data[index])
  }
  Ok((subfunction, payload))
}

///|
/// Decode the communication event counter response.
pub fn decode_comm_event_counter(
  request : Frame,
  response : Frame,
) -> Result[(UInt16, UInt16), ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 4 {
    return Err(InvalidLength)
  }
  Ok(
    (
      (response.pdu.data[0].to_uint16() << 8) | response.pdu.data[1].to_uint16(),
      (response.pdu.data[2].to_uint16() << 8) | response.pdu.data[3].to_uint16(),
    ),
  )
}

///|
/// Decode an exception-status response.
pub fn decode_exception_status(
  request : Frame,
  response : Frame,
) -> Result[Byte, ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() != 1 {
    Err(InvalidLength)
  } else {
    Ok(response.pdu.data[0])
  }
}

///|
/// Decode a Report Server ID response into its raw payload.
pub fn decode_server_id(
  request : Frame,
  response : Frame,
) -> Result[Array[Byte], ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 1 {
    Err(Incomplete)
  } else {
    Ok(copy_bytes(response.pdu.data))
  }
}

///|
/// Decode a FIFO response into the queue values.
pub fn decode_fifo_queue(
  request : Frame,
  response : Frame,
) -> Result[Array[UInt16], ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 4 {
    return Err(Incomplete)
  }
  let byte_count = (response.pdu.data[0].to_uint16() << 8) |
    response.pdu.data[1].to_uint16()
  let fifo_count = (response.pdu.data[2].to_uint16() << 8) |
    response.pdu.data[3].to_uint16()
  if byte_count.to_int() != response.pdu.data.length() - 2 ||
    fifo_count.to_int() * 2 != byte_count.to_int() - 2 {
    return Err(InvalidByteCount)
  }
  let values : Array[UInt16] = []
  for index in 0..<fifo_count.to_int() {
    let offset = 4 + index * 2
    values.push(
      (response.pdu.data[offset].to_uint16() << 8) |
      response.pdu.data[offset + 1].to_uint16(),
    )
  }
  Ok(values)
}

///|
/// Check an ordinary write response without decoding its fields.
pub fn is_write_echo(request : Frame, response : Frame) -> Bool {
  match validate_response_header(request, response) {
    Ok(_) => !response.is_exception() && response.pdu.data == request.pdu.data
    Err(_) => false
  }
}

///|
/// Return a short response quality classification for metrics.
pub fn response_quality(request : Frame, response : Frame) -> String {
  match validate_response_header(request, response) {
    Err(UnitMismatch) => "unit-mismatch"
    Err(InvalidFunction) => "function-mismatch"
    Err(_) => "malformed"
    Ok(_) => if response.is_exception() { "exception" } else { "ok" }
  }
}
