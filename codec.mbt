///|
/// Encode a frame as Modbus RTU.
pub fn encode_rtu(frame : Frame) -> Array[Byte] {
  let body = [frame.unit_id, frame.pdu.function].add(frame.pdu.data)
  body.add(crc_bytes(body))
}

///|
/// Decode one complete Modbus RTU frame.
pub fn decode_rtu(bytes : Array[Byte]) -> Result[Frame, ModbusError] {
  if bytes.length() < 4 {
    return Err(Incomplete)
  }
  let payload = bytes.view(start=0, end=bytes.length() - 2).to_owned()
  let expected = crc16(payload)
  let received = bytes[bytes.length() - 2].to_uint16() +
    bytes[bytes.length() - 1].to_uint16().shl(8)
  if expected != received {
    return Err(InvalidChecksum)
  }
  let data : Array[Byte] = []
  for i in 2..<(bytes.length() - 2) {
    data.push(bytes[i])
  }
  if data.length() == 0 {
    Err(InvalidLength)
  } else {
    Ok({ unit_id: bytes[0], pdu: { function: bytes[1], data } })
  }
}

///|
/// Encode a frame as Modbus TCP, using a caller-provided transaction id.
pub fn encode_tcp(transaction_id : UInt16, frame : Frame) -> Array[Byte] {
  let length = 2 + frame.pdu.data.length()
  [
    (transaction_id >> 8).to_byte(),
    transaction_id.to_byte(),
    0,
    0,
    (length >> 8).to_byte(),
    length.to_byte(),
    frame.unit_id,
    frame.pdu.function,
  ].add(frame.pdu.data)
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
  if length.to_int() != bytes.length() - 6 {
    return Err(InvalidLength)
  }
  let data : Array[Byte] = []
  for i in 8..<bytes.length() {
    data.push(bytes[i])
  }
  Ok(
    (
      bytes[0].to_uint16().shl(8) + bytes[1].to_uint16(),
      { unit_id: bytes[6], pdu: { function: bytes[7], data } },
    ),
  )
}

///|
/// Encode a frame as Modbus ASCII, including `:` prefix and CRLF suffix.
pub fn encode_ascii(frame : Frame) -> Array[Byte] {
  let body = [frame.unit_id, frame.pdu.function].add(frame.pdu.data)
  let with_lrc = body.add([lrc(body)])
  let out : Array[Byte] = [58]
  for byte in with_lrc {
    out.push(hex_nibble(byte.shr(4)))
    out.push(hex_nibble(byte.land(15)))
  }
  out.push(13)
  out.push(10)
  out
}

///|
/// Decode one complete Modbus ASCII frame.
pub fn decode_ascii(bytes : Array[Byte]) -> Result[Frame, ModbusError] {
  if bytes.length() < 7 ||
    bytes[0] != 58 ||
    bytes[bytes.length() - 2] != 13 ||
    bytes[bytes.length() - 1] != 10 {
    return Err(InvalidAscii)
  }
  let decoded : Array[Byte] = []
  for i in 1..<(bytes.length() - 2) {
    if i % 2 == 1 {
      match parse_hex_byte(bytes[i], bytes[i + 1]) {
        Ok(byte) => decoded.push(byte)
        Err(error) => return Err(error)
      }
    }
  }
  if decoded.length() < 3 {
    return Err(InvalidLength)
  }
  let payload = decoded.view(start=0, end=decoded.length() - 1).to_owned()
  if lrc(payload) != decoded[decoded.length() - 1] {
    return Err(InvalidChecksum)
  }
  let data : Array[Byte] = []
  for i in 2..<(decoded.length() - 1) {
    data.push(decoded[i])
  }
  Ok({ unit_id: decoded[0], pdu: { function: decoded[1], data } })
}
