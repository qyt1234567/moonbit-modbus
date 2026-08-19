///|
/// Register byte order used when mapping multi-register values.
pub(all) enum RegisterByteOrder {
  BigEndian
  LittleEndian
} derive(Debug, Eq)

///|
/// Word order used for values wider than one register.
pub(all) enum RegisterWordOrder {
  HighWordFirst
  LowWordFirst
} derive(Debug, Eq)

///|
pub fn register_byte_order_name(order : RegisterByteOrder) -> String {
  match order {
    BigEndian => "big-endian"
    LittleEndian => "little-endian"
  }
}

///|
pub fn register_word_order_name(order : RegisterWordOrder) -> String {
  match order {
    HighWordFirst => "high-word-first"
    LowWordFirst => "low-word-first"
  }
}

///|
/// Convert one register to two bytes in the requested byte order.
pub fn register_to_bytes(
  value : UInt16,
  order : RegisterByteOrder,
) -> Array[Byte] {
  match order {
    BigEndian => [value >> 8, value].map(x => x.to_byte())
    LittleEndian => [value, value >> 8].map(x => x.to_byte())
  }
}

///|
/// Decode two bytes as one register.
pub fn bytes_to_register(
  bytes : Array[Byte],
  offset : Int,
  order : RegisterByteOrder,
) -> Result[UInt16, ModbusError] {
  if offset < 0 || offset + 2 > bytes.length() {
    return Err(Incomplete)
  }
  match order {
    BigEndian =>
      Ok((bytes[offset].to_uint16() << 8) | bytes[offset + 1].to_uint16())
    LittleEndian =>
      Ok((bytes[offset + 1].to_uint16() << 8) | bytes[offset].to_uint16())
  }
}

///|
/// Encode an unsigned 32-bit value into two registers.
pub fn u32_to_registers(
  value : UInt,
  word_order : RegisterWordOrder,
) -> Array[UInt16] {
  let high = (value >> 16).to_uint16()
  let low = value.to_uint16()
  match word_order {
    HighWordFirst => [high, low]
    LowWordFirst => [low, high]
  }
}

///|
/// Decode two registers as an unsigned 32-bit value.
pub fn registers_to_u32(
  values : Array[UInt16],
  word_order : RegisterWordOrder,
) -> Result[UInt, ModbusError] {
  if values.length() < 2 {
    return Err(Incomplete)
  }
  match word_order {
    HighWordFirst => Ok((values[0].to_uint() << 16) | values[1].to_uint())
    LowWordFirst => Ok((values[1].to_uint() << 16) | values[0].to_uint())
  }
}

///|
/// Encode a signed 32-bit value using two's-complement bits.
pub fn i32_to_registers(
  value : Int,
  word_order : RegisterWordOrder,
) -> Array[UInt16] {
  u32_to_registers(value.reinterpret_as_uint(), word_order)
}

///|
/// Decode a signed 32-bit value from two registers.
pub fn registers_to_i32(
  values : Array[UInt16],
  word_order : RegisterWordOrder,
) -> Result[Int, ModbusError] {
  match registers_to_u32(values, word_order) {
    Ok(value) => Ok(value.reinterpret_as_int())
    Err(error) => Err(error)
  }
}

///|
/// Encode a 64-bit value into four registers.
pub fn u64_to_registers(
  value : UInt64,
  word_order : RegisterWordOrder,
) -> Array[UInt16] {
  let words : Array[UInt16] = [
    (value >> 48).to_uint16(),
    (value >> 32).to_uint16(),
    (value >> 16).to_uint16(),
    value.to_uint16(),
  ]
  match word_order {
    HighWordFirst => words
    LowWordFirst => [words[3], words[2], words[1], words[0]]
  }
}

///|
/// Decode four registers as a 64-bit value.
pub fn registers_to_u64(
  values : Array[UInt16],
  word_order : RegisterWordOrder,
) -> Result[UInt64, ModbusError] {
  if values.length() < 4 {
    return Err(Incomplete)
  }
  let words = match word_order {
    HighWordFirst => values
    LowWordFirst => [values[3], values[2], values[1], values[0]]
  }
  Ok(
    (words[0].to_uint64() << 48) |
    (words[1].to_uint64() << 32) |
    (words[2].to_uint64() << 16) |
    words[3].to_uint64(),
  )
}

///|
/// Encode a Float in IEEE-754 binary32 form as two registers.
pub fn f32_to_registers(
  value : Float,
  word_order : RegisterWordOrder,
) -> Array[UInt16] {
  u32_to_registers(value.reinterpret_as_uint(), word_order)
}

///|
/// Decode two registers as an IEEE-754 binary32 Float.
pub fn registers_to_f32(
  values : Array[UInt16],
  word_order : RegisterWordOrder,
) -> Result[Float, ModbusError] {
  match registers_to_u32(values, word_order) {
    Ok(value) => Ok(Float::reinterpret_from_uint(value))
    Err(error) => Err(error)
  }
}

///|
/// Convert an array of registers to bytes with a selected byte order.
pub fn registers_to_bytes(
  values : Array[UInt16],
  order : RegisterByteOrder,
) -> Array[Byte] {
  let out : Array[Byte] = []
  for value in values {
    let encoded = register_to_bytes(value, order)
    out.push(encoded[0])
    out.push(encoded[1])
  }
  out
}

///|
/// Convert an even-length byte array to registers.
pub fn bytes_to_registers(
  bytes : Array[Byte],
  order : RegisterByteOrder,
) -> Result[Array[UInt16], ModbusError] {
  if bytes.length() % 2 != 0 {
    return Err(InvalidLength)
  }
  let out : Array[UInt16] = []
  for offset in 0..<(bytes.length() / 2) {
    match bytes_to_register(bytes, offset * 2, order) {
      Ok(value) => out.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
/// Rotate bytes inside every register, useful for devices with byte-swapped words.
pub fn swap_register_bytes(values : Array[UInt16]) -> Array[UInt16] {
  values.map(value => (value << 8) | (value >> 8))
}

///|
/// Reverse register order in a copied array.
pub fn reverse_registers(values : Array[UInt16]) -> Array[UInt16] {
  let out : Array[UInt16] = []
  let mut index = values.length() - 1
  while index >= 0 {
    out.push(values[index])
    index -= 1
  }
  out
}

///|
/// A bounds-checked cursor over an owned register array.
pub(all) struct RegisterCursor {
  values : Array[UInt16]
  mut position : Int
}

///|
pub fn RegisterCursor::new(values : Array[UInt16]) -> RegisterCursor {
  { values, position: 0 }
}

///|
pub fn RegisterCursor::position(self : RegisterCursor) -> Int {
  self.position
}

///|
pub fn RegisterCursor::remaining(self : RegisterCursor) -> Int {
  self.values.length() - self.position
}

///|
pub fn RegisterCursor::at_end(self : RegisterCursor) -> Bool {
  self.position >= self.values.length()
}

///|
pub fn RegisterCursor::read_u16(
  self : RegisterCursor,
) -> Result[UInt16, ModbusError] {
  if self.position >= self.values.length() {
    Err(Incomplete)
  } else {
    let value = self.values[self.position]
    self.position += 1
    Ok(value)
  }
}

///|
pub fn RegisterCursor::read_i16(
  self : RegisterCursor,
) -> Result[Int, ModbusError] {
  match self.read_u16() {
    Ok(value) => Ok(signed_register(value))
    Err(error) => Err(error)
  }
}

///|
pub fn RegisterCursor::read_u32(
  self : RegisterCursor,
  order : RegisterWordOrder,
) -> Result[UInt, ModbusError] {
  match (self.read_u16(), self.read_u16()) {
    (Ok(first), Ok(second)) => registers_to_u32([first, second], order)
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }
}

///|
pub fn RegisterCursor::read_i32(
  self : RegisterCursor,
  order : RegisterWordOrder,
) -> Result[Int, ModbusError] {
  match self.read_u32(order) {
    Ok(value) => Ok(value.reinterpret_as_int())
    Err(error) => Err(error)
  }
}

///|
pub fn RegisterCursor::read_u64(
  self : RegisterCursor,
  order : RegisterWordOrder,
) -> Result[UInt64, ModbusError] {
  let values : Array[UInt16] = []
  for _ in 0..<4 {
    match self.read_u16() {
      Ok(value) => values.push(value)
      Err(error) => return Err(error)
    }
  }
  registers_to_u64(values, order)
}

///|
pub fn RegisterCursor::read_f32(
  self : RegisterCursor,
  order : RegisterWordOrder,
) -> Result[Float, ModbusError] {
  match self.read_u32(order) {
    Ok(value) => Ok(Float::reinterpret_from_uint(value))
    Err(error) => Err(error)
  }
}

///|
pub fn RegisterCursor::skip(
  self : RegisterCursor,
  count : Int,
) -> Result[Unit, ModbusError] {
  if count < 0 || self.position + count > self.values.length() {
    Err(Incomplete)
  } else {
    self.position += count
    Ok(())
  }
}

///|
pub fn RegisterCursor::seek(
  self : RegisterCursor,
  position : Int,
) -> Result[Unit, ModbusError] {
  if position < 0 || position > self.values.length() {
    Err(InvalidAddress)
  } else {
    self.position = position
    Ok(())
  }
}

///|
/// A register writer that grows only up to a configured capacity.
pub(all) struct RegisterWriter {
  values : Array[UInt16]
  capacity : Int
}

///|
pub fn RegisterWriter::new(
  capacity : Int,
) -> Result[RegisterWriter, ModbusError] {
  if capacity < 0 || capacity > 125 {
    Err(CapacityExceeded)
  } else {
    Ok({ values: [], capacity })
  }
}

///|
pub fn RegisterWriter::length(self : RegisterWriter) -> Int {
  self.values.length()
}

///|
pub fn RegisterWriter::remaining(self : RegisterWriter) -> Int {
  self.capacity - self.values.length()
}

///|
pub fn RegisterWriter::push(
  self : RegisterWriter,
  value : UInt16,
) -> Result[Unit, ModbusError] {
  if self.values.length() >= self.capacity {
    Err(CapacityExceeded)
  } else {
    self.values.push(value)
    Ok(())
  }
}

///|
pub fn RegisterWriter::push_i16(
  self : RegisterWriter,
  value : Int,
) -> Result[Unit, ModbusError] {
  self.push(value.to_uint16())
}

///|
pub fn RegisterWriter::push_u32(
  self : RegisterWriter,
  value : UInt,
  order : RegisterWordOrder,
) -> Result[Unit, ModbusError] {
  for word in u32_to_registers(value, order) {
    match self.push(word) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
pub fn RegisterWriter::push_u64(
  self : RegisterWriter,
  value : UInt64,
  order : RegisterWordOrder,
) -> Result[Unit, ModbusError] {
  for word in u64_to_registers(value, order) {
    match self.push(word) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
pub fn RegisterWriter::push_f32(
  self : RegisterWriter,
  value : Float,
  order : RegisterWordOrder,
) -> Result[Unit, ModbusError] {
  for word in f32_to_registers(value, order) {
    match self.push(word) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
pub fn RegisterWriter::to_array(self : RegisterWriter) -> Array[UInt16] {
  copy_registers(self.values)
}

///|
fn copy_registers(values : Array[UInt16]) -> Array[UInt16] {
  let out : Array[UInt16] = []
  for value in values {
    out.push(value)
  }
  out
}
