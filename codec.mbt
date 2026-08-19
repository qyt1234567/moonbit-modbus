///|
/// Return the PDU bytes following the unit identifier.
pub fn pdu_bytes(frame : Frame) -> Array[Byte] {
  let out : Array[Byte] = [frame.pdu.function]
  for byte in frame.pdu.data {
    out.push(byte)
  }
  out
}

///|
/// Return the RTU payload before its two-byte CRC.
pub fn rtu_payload(frame : Frame) -> Array[Byte] {
  let out : Array[Byte] = [frame.unit_id, frame.pdu.function]
  for byte in frame.pdu.data {
    out.push(byte)
  }
  out
}

///|
/// Encode a frame as Modbus RTU.
pub fn encode_rtu(frame : Frame) -> Array[Byte] {
  let body = rtu_payload(frame)
  let out : Array[Byte] = []
  for byte in body {
    out.push(byte)
  }
  let checksum = crc_bytes(body)
  out.push(checksum[0])
  out.push(checksum[1])
  out
}

///|
/// Checked RTU encoder for code that wants validation errors instead of a raw frame.
pub fn try_encode_rtu(frame : Frame) -> Result[Array[Byte], ModbusError] {
  match validate_wire_frame(frame, true) {
    Ok(_) => Ok(encode_rtu(frame))
    Err(error) => Err(error)
  }
}

///|
/// Decode one complete Modbus RTU frame.
pub fn decode_rtu(bytes : Array[Byte]) -> Result[Frame, ModbusError] {
  if bytes.length() < 4 {
    return Err(Incomplete)
  }
  if bytes.length() > 260 {
    return Err(InvalidLength)
  }
  match validate_unit(bytes[0], true) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let payload = copy_range(bytes, 0, bytes.length() - 2)
  let payload = match payload {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let expected = crc16(payload)
  let received = bytes[bytes.length() - 2].to_uint16() +
    (bytes[bytes.length() - 1].to_uint16() << 8)
  if expected != received {
    return Err(InvalidChecksum)
  }
  let data : Array[Byte] = []
  for i in 2..<(bytes.length() - 2) {
    data.push(bytes[i])
  }
  if data.length() == 0 {
    return Err(InvalidLength)
  }
  Ok({ unit_id: bytes[0], pdu: { function: bytes[1], data } })
}

///|
/// Encode a frame as Modbus TCP, using a caller-provided transaction id.
pub fn encode_tcp(transaction_id : UInt16, frame : Frame) -> Array[Byte] {
  let length = 2 + frame.pdu.data.length()
  let out : Array[Byte] = [
    (transaction_id >> 8).to_byte(),
    transaction_id.to_byte(),
    0,
    0,
    (length >> 8).to_byte(),
    length.to_byte(),
    frame.unit_id,
    frame.pdu.function,
  ]
  for byte in frame.pdu.data {
    out.push(byte)
  }
  out
}

///|
/// Checked TCP encoder.
pub fn try_encode_tcp(
  transaction_id : UInt16,
  frame : Frame,
) -> Result[Array[Byte], ModbusError] {
  if frame.pdu.data.length() > 251 {
    return Err(InvalidLength)
  }
  match validate_wire_frame(frame, true) {
    Ok(_) => Ok(encode_tcp(transaction_id, frame))
    Err(error) => Err(error)
  }
}

///|
/// Decode one complete Modbus TCP ADU and return its transaction id.
pub fn decode_tcp(bytes : Array[Byte]) -> Result[(UInt16, Frame), ModbusError] {
  if bytes.length() < 8 {
    return Err(Incomplete)
  }
  if bytes[2] != 0 || bytes[3] != 0 {
    return Err(InvalidMbap)
  }
  let length = bytes[4].to_uint16().shl(8) + bytes[5].to_uint16()
  if length < 2 || length > 253 {
    return Err(InvalidLength)
  }
  if length.to_int() != bytes.length() - 6 {
    return Err(InvalidLength)
  }
  match validate_unit(bytes[6], true) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let data : Array[Byte] = []
  for i in 8..<bytes.length() {
    data.push(bytes[i])
  }
  if data.length() == 0 {
    return Err(InvalidLength)
  }
  Ok(
    (
      (bytes[0].to_uint16() << 8) | bytes[1].to_uint16(),
      { unit_id: bytes[6], pdu: { function: bytes[7], data } },
    ),
  )
}

///|
/// Encode a frame as Modbus ASCII, including `:` prefix and CRLF suffix.
pub fn encode_ascii(frame : Frame) -> Array[Byte] {
  let body = rtu_payload(frame)
  let with_lrc : Array[Byte] = []
  for byte in body {
    with_lrc.push(byte)
  }
  with_lrc.push(lrc(body))
  let out : Array[Byte] = [58]
  for byte in with_lrc {
    out.push(hex_nibble(byte >> 4))
    out.push(hex_nibble(byte & 15))
  }
  out.push(13)
  out.push(10)
  out
}

///|
/// Checked ASCII encoder.
pub fn try_encode_ascii(frame : Frame) -> Result[Array[Byte], ModbusError] {
  if frame.pdu.data.length() > 251 {
    return Err(InvalidLength)
  }
  match validate_wire_frame(frame, true) {
    Ok(_) => Ok(encode_ascii(frame))
    Err(error) => Err(error)
  }
}

///|
/// Decode one complete Modbus ASCII frame.
pub fn decode_ascii(bytes : Array[Byte]) -> Result[Frame, ModbusError] {
  if bytes.length() < 7 {
    return Err(Incomplete)
  }
  if bytes[0] != 58 {
    return Err(InvalidAscii)
  }
  if bytes[bytes.length() - 2] != 13 || bytes[bytes.length() - 1] != 10 {
    return Err(Incomplete)
  }
  let hex_length = bytes.length() - 3
  if hex_length % 2 != 0 {
    return Err(InvalidAscii)
  }
  let decoded : Array[Byte] = []
  let mut i = 1
  while i < bytes.length() - 2 {
    match parse_hex_byte(bytes[i], bytes[i + 1]) {
      Ok(byte) => decoded.push(byte)
      Err(error) => return Err(error)
    }
    i += 2
  }
  if decoded.length() < 3 {
    return Err(InvalidLength)
  }
  match validate_unit(decoded[0], true) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let payload = copy_range(decoded, 0, decoded.length() - 1)
  let payload = match payload {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if lrc(payload) != decoded[decoded.length() - 1] {
    return Err(InvalidChecksum)
  }
  let data : Array[Byte] = []
  for index in 2..<(decoded.length() - 1) {
    data.push(decoded[index])
  }
  Ok({ unit_id: decoded[0], pdu: { function: decoded[1], data } })
}

///|
/// Return the encoded size of a frame on a transport.
pub fn encoded_length(mode : Mode, frame : Frame) -> Int {
  match mode {
    Rtu => 4 + frame.pdu.data.length()
    Ascii => 7 + (frame.pdu.data.length() + 2) * 2
    Tcp => 8 + frame.pdu.data.length()
  }
}

///|
/// Return the expected TCP ADU size from a partial header.
pub fn expected_tcp_length(bytes : Array[Byte]) -> Result[Int, ModbusError] {
  if bytes.length() < 6 {
    return Err(Incomplete)
  }
  if bytes[2] != 0 || bytes[3] != 0 {
    return Err(InvalidMbap)
  }
  let length = bytes[4].to_int() * 256 + bytes[5].to_int()
  if length < 2 || length > 253 {
    Err(InvalidLength)
  } else {
    Ok(length + 6)
  }
}

///|
/// Return a complete ASCII frame boundary if CRLF is present.
pub fn ascii_boundary(bytes : Array[Byte]) -> Int? {
  if bytes.length() >= 2 &&
    bytes[bytes.length() - 2] == 13 &&
    bytes[bytes.length() - 1] == 10 {
    Some(bytes.length())
  } else {
    None
  }
}

///|
/// Decode a complete frame when the transport does not carry a TCP transaction id.
pub fn decode_mode(
  mode : Mode,
  bytes : Array[Byte],
) -> Result[Frame, ModbusError] {
  match mode {
    Rtu => decode_rtu(bytes)
    Ascii => decode_ascii(bytes)
    Tcp =>
      match decode_tcp(bytes) {
        Ok((_, frame)) => Ok(frame)
        Err(error) => Err(error)
      }
  }
}

///|
/// Encode a frame for a mode; TCP uses transaction id zero for this convenience API.
pub fn encode_mode(mode : Mode, frame : Frame) -> Array[Byte] {
  match mode {
    Rtu => encode_rtu(frame)
    Ascii => encode_ascii(frame)
    Tcp => encode_tcp(0, frame)
  }
}

///|
/// Checked transport encoder with an explicit TCP transaction id.
pub fn try_encode_mode(
  mode : Mode,
  transaction_id : UInt16,
  frame : Frame,
) -> Result[Array[Byte], ModbusError] {
  match mode {
    Rtu => try_encode_rtu(frame)
    Ascii => try_encode_ascii(frame)
    Tcp => try_encode_tcp(transaction_id, frame)
  }
}

///|
/// Decode an encoded frame and preserve a TCP transaction identifier when present.
pub fn decode_transaction(
  mode : Mode,
  bytes : Array[Byte],
) -> Result[(UInt16, Frame), ModbusError] {
  match mode {
    Tcp => decode_tcp(bytes)
    Rtu =>
      match decode_rtu(bytes) {
        Ok(frame) => Ok((0, frame))
        Err(error) => Err(error)
      }
    Ascii =>
      match decode_ascii(bytes) {
        Ok(frame) => Ok((0, frame))
        Err(error) => Err(error)
      }
  }
}

///|
/// Calculate how many bytes are needed for the shortest frame of a mode.
pub fn minimum_frame_length(mode : Mode) -> Int {
  match mode {
    Rtu => 4
    Ascii => 7
    Tcp => 8
  }
}
