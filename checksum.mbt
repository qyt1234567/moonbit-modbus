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
