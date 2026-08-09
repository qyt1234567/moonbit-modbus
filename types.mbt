///|
/// A Modbus wire mode.
pub enum Mode {
  Rtu
  Ascii
  Tcp
}

///|
/// Standard constructors kept as named entry points for configuration files.
pub fn rtu_mode() -> Mode {
  Rtu
}

///|
pub fn ascii_mode() -> Mode {
  Ascii
}

///|
pub fn tcp_mode() -> Mode {
  Tcp
}

///|
/// A Modbus application data unit without transport framing.
pub(all) struct Pdu {
  function : Byte
  data : Array[Byte]
}

///|
/// A decoded frame, including the unit identifier.
pub(all) struct Frame {
  unit_id : Byte
  pdu : Pdu
}

///|
/// Errors produced by the protocol core.
pub enum ModbusError {
  Incomplete
  InvalidLength
  InvalidChecksum
  InvalidAscii
  InvalidMbap
}

///|
/// A request for reading holding registers (function 03).
pub fn read_holding(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Frame {
  {
    unit_id,
    pdu: {
      function: 3,
      data: [
        address.shr(8).to_byte(),
        address.to_byte(),
        quantity.shr(8).to_byte(),
        quantity.to_byte(),
      ],
    },
  }
}

///|
/// A request for writing one holding register (function 06).
pub fn write_single_register(
  unit_id : Byte,
  address : UInt16,
  value : UInt16,
) -> Frame {
  {
    unit_id,
    pdu: {
      function: 6,
      data: [
        address.shr(8).to_byte(),
        address.to_byte(),
        value.shr(8).to_byte(),
        value.to_byte(),
      ],
    },
  }
}

///|
/// Decode a signed 16-bit register.
pub fn signed_register(value : UInt16) -> Int {
  let n = value.to_int()
  if n >= 32768 {
    n - 65536
  } else {
    n
  }
}

///|
/// Decode two registers as the raw IEEE-754 single precision words.
pub fn float_words(high : UInt16, low : UInt16) -> UInt64 {
  (high.to_uint64() << 16) + low.to_uint64()
}

///|
/// Decode the data portion of a register response.
pub fn registers(frame : Frame) -> Result[Array[UInt16], ModbusError] {
  if frame.pdu.data.length() % 2 != 0 {
    return Err(InvalidLength)
  }
  let out : Array[UInt16] = []
  for i in 0..<(frame.pdu.data.length() / 2) {
    out.push(
      frame.pdu.data[i * 2].to_uint16().shl(8) +
      frame.pdu.data[i * 2 + 1].to_uint16(),
    )
  }
  Ok(out)
}
