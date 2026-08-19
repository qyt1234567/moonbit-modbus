///|
/// Modbus polynomial CRC16, low byte first on the wire.
pub fn crc16(bytes : Array[Byte]) -> UInt16 {
  let mut crc : UInt16 = 0xFFFF
  for byte in bytes {
    crc = crc ^ byte.to_uint16()
    for _ in 0..<8 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ 0xA001
      } else {
        crc = crc >> 1
      }
    }
  }
  crc
}

///|
/// Return CRC bytes in Modbus RTU order.
pub fn crc_bytes(bytes : Array[Byte]) -> Array[Byte] {
  let crc = crc16(bytes)
  [crc.to_byte(), crc.shr(8).to_byte()]
}

///|
/// LRC used by Modbus ASCII.
pub fn lrc(bytes : Array[Byte]) -> Byte {
  let mut sum : Byte = 0
  for byte in bytes {
    sum = sum + byte
  }
  (0 - sum.to_int()).to_byte()
}

///|
/// Convert one ASCII hex byte into a binary byte.
pub fn parse_hex_byte(high : Byte, low : Byte) -> Result[Byte, ModbusError] {
  fn nibble(x : Byte) -> Byte {
    if x >= 48 && x <= 57 {
      x - 48
    } else if x >= 65 && x <= 70 {
      x - 55
    } else if x >= 97 && x <= 102 {
      x - 87
    } else {
      255
    }
  }
  let h = nibble(high)
  let l = nibble(low)
  if h == 255 || l == 255 {
    Err(InvalidAscii)
  } else {
    Ok(h.shl(4) + l)
  }
}

///|
fn hex_nibble(value : Byte) -> Byte {
  if value < 10 {
    value + 48
  } else {
    value + 55
  }
}

///|
/// Update a CRC16 accumulator with one byte.
pub fn crc16_update(crc : UInt16, byte : Byte) -> UInt16 {
  let mut current = crc ^ byte.to_uint16()
  for _ in 0..<8 {
    if (current & 1) == 1 {
      current = (current >> 1) ^ 0xA001
    } else {
      current = current >> 1
    }
  }
  current
}

///|
/// Compute CRC16 for a half-open range without allocating a slice.
pub fn crc16_range(
  bytes : Array[Byte],
  start : Int,
  end : Int,
) -> Result[UInt16, ModbusError] {
  if start < 0 || end < start || end > bytes.length() {
    return Err(InvalidLength)
  }
  let mut crc : UInt16 = 0xFFFF
  for i in start..<end {
    crc = crc16_update(crc, bytes[i])
  }
  Ok(crc)
}

///|
/// Incremental CRC16 accumulator for serial readers.
pub(all) struct Crc16State {
  mut value : UInt16
}

///|
pub fn Crc16State::new() -> Crc16State {
  { value: 0xFFFF }
}

///|
pub fn Crc16State::update(self : Crc16State, bytes : Array[Byte]) -> Unit {
  for byte in bytes {
    self.value = crc16_update(self.value, byte)
  }
}

///|
pub fn Crc16State::update_byte(self : Crc16State, byte : Byte) -> Unit {
  self.value = crc16_update(self.value, byte)
}

///|
pub fn Crc16State::finalize(self : Crc16State) -> UInt16 {
  self.value
}

///|
pub fn Crc16State::finalize_bytes(self : Crc16State) -> Array[Byte] {
  [self.value.to_byte(), (self.value >> 8).to_byte()]
}

///|
/// Compute the LRC from a running sum, using the Modbus two's-complement rule.
pub fn lrc_from_sum(sum : Byte) -> Byte {
  (0 - sum.to_int()).to_byte()
}

///|
/// Return both the LRC and the modulo-256 sum for diagnostics.
pub fn lrc_with_sum(bytes : Array[Byte]) -> (Byte, Byte) {
  let mut sum : Byte = 0
  for byte in bytes {
    sum = sum + byte
  }
  (lrc_from_sum(sum), sum)
}

///|
/// Encode an owned byte array as uppercase hexadecimal ASCII.
pub fn encode_hex(bytes : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  for byte in bytes {
    out.push(hex_nibble(byte >> 4))
    out.push(hex_nibble(byte & 15))
  }
  out
}

///|
fn hex_value(value : Byte) -> Byte? {
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
/// Decode an even-length hexadecimal ASCII array.
pub fn decode_hex(bytes : Array[Byte]) -> Result[Array[Byte], ModbusError] {
  if bytes.length() % 2 != 0 {
    return Err(InvalidAscii)
  }
  let out : Array[Byte] = []
  for i in 0..<(bytes.length() / 2) {
    match (hex_value(bytes[i * 2]), hex_value(bytes[i * 2 + 1])) {
      (Some(high), Some(low)) => out.push((high << 4) | low)
      _ => return Err(InvalidAscii)
    }
  }
  Ok(out)
}

///|
/// Verify a CRC16 trailer in low-byte-first wire order.
pub fn verify_crc16(bytes : Array[Byte]) -> Result[Unit, ModbusError] {
  if bytes.length() < 2 {
    return Err(Incomplete)
  }
  let payload = match crc16_range(bytes, 0, bytes.length() - 2) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let received = bytes[bytes.length() - 2].to_uint16() |
    (bytes[bytes.length() - 1].to_uint16() << 8)
  if payload == received {
    Ok(())
  } else {
    Err(InvalidChecksum)
  }
}

///|
/// Verify an LRC trailer at the end of a byte array.
pub fn verify_lrc(bytes : Array[Byte]) -> Result[Unit, ModbusError] {
  if bytes.length() < 2 {
    return Err(Incomplete)
  }
  let payload = match copy_range(bytes, 0, bytes.length() - 1) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if lrc(payload) == bytes[bytes.length() - 1] {
    Ok(())
  } else {
    Err(InvalidChecksum)
  }
}
