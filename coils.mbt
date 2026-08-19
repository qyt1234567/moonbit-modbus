///|
/// Pack boolean values into Modbus LSB-first coil bytes.
pub fn pack_bits(values : Array[Bool]) -> Array[Byte] {
  let out : Array[Byte] = []
  let byte_count = (values.length() + 7) / 8
  for _ in 0..<byte_count {
    out.push(0)
  }
  for index, value in values {
    if value {
      out[index / 8] = out[index / 8] | (1 << (index % 8)).to_byte()
    }
  }
  out
}

///|
/// Unpack exactly `quantity` coil values from LSB-first bytes.
pub fn unpack_bits(
  bytes : Array[Byte],
  quantity : Int,
) -> Result[Array[Bool], ModbusError] {
  if quantity < 0 {
    return Err(InvalidQuantity)
  }
  let expected = (quantity + 7) / 8
  if bytes.length() != expected {
    return Err(InvalidByteCount)
  }
  let out : Array[Bool] = []
  for index in 0..<quantity {
    out.push((bytes[index / 8] & (1 << (index % 8)).to_byte()) != 0)
  }
  Ok(out)
}

///|
/// Read a single bit from a packed byte array.
pub fn get_bit(bytes : Array[Byte], index : Int) -> Result[Bool, ModbusError] {
  if index < 0 || index / 8 >= bytes.length() {
    Err(InvalidAddress)
  } else {
    Ok((bytes[index / 8] & (1 << (index % 8)).to_byte()) != 0)
  }
}

///|
/// Set a single bit in a packed byte array.
pub fn set_bit(
  bytes : Array[Byte],
  index : Int,
  value : Bool,
) -> Result[Unit, ModbusError] {
  if index < 0 || index / 8 >= bytes.length() {
    return Err(InvalidAddress)
  }
  let mask = (1 << (index % 8)).to_byte()
  if value {
    bytes[index / 8] = bytes[index / 8] | mask
  } else {
    bytes[index / 8] = bytes[index / 8] & (0xFF ^ mask)
  }
  Ok(())
}

///|
/// Count the set bits in a packed byte array.
pub fn count_bits(bytes : Array[Byte]) -> Int {
  let mut total = 0
  for byte in bytes {
    let mut value = byte
    for _ in 0..<8 {
      if (value & 1) != 0 {
        total += 1
      }
      value = value >> 1
    }
  }
  total
}

///|
/// A mutable bounded bit vector for coils and discrete inputs.
pub(all) struct BitVector {
  length : Int
  storage : Array[Byte]
}

///|
/// Create a zero-filled bit vector.
pub fn BitVector::new(length : Int) -> Result[BitVector, ModbusError] {
  if length < 0 || length > 65536 {
    return Err(CapacityExceeded)
  }
  let storage : Array[Byte] = []
  for _ in 0..<((length + 7) / 8) {
    storage.push(0)
  }
  Ok({ length, storage })
}

///|
pub fn BitVector::from_bits(values : Array[Bool]) -> BitVector {
  { length: values.length(), storage: pack_bits(values) }
}

///|
pub fn BitVector::length(self : BitVector) -> Int {
  self.length
}

///|
pub fn BitVector::byte_length(self : BitVector) -> Int {
  self.storage.length()
}

///|
pub fn BitVector::get(
  self : BitVector,
  index : Int,
) -> Result[Bool, ModbusError] {
  if index < 0 || index >= self.length {
    Err(InvalidAddress)
  } else {
    get_bit(self.storage, index)
  }
}

///|
pub fn BitVector::set(
  self : BitVector,
  index : Int,
  value : Bool,
) -> Result[Unit, ModbusError] {
  if index < 0 || index >= self.length {
    Err(InvalidAddress)
  } else {
    set_bit(self.storage, index, value)
  }
}

///|
pub fn BitVector::fill(self : BitVector, value : Bool) -> Unit {
  let fill : Byte = if value { 0xFF } else { 0 }
  for index in 0..<self.storage.length() {
    self.storage[index] = fill
  }
  if value && self.length % 8 != 0 && self.storage.length() > 0 {
    self.storage[self.storage.length() - 1] = (1 << (self.length % 8)).to_byte() -
      1
  }
}

///|
pub fn BitVector::to_bits(self : BitVector) -> Array[Bool] {
  let out : Array[Bool] = []
  for index in 0..<self.length {
    out.push((self.storage[index / 8] & (1 << (index % 8)).to_byte()) != 0)
  }
  out
}

///|
pub fn BitVector::to_bytes(self : BitVector) -> Array[Byte] {
  copy_bytes(self.storage)
}

///|
pub fn BitVector::count(self : BitVector) -> Int {
  let mut count = 0
  for index in 0..<self.length {
    if (self.storage[index / 8] & (1 << (index % 8)).to_byte()) != 0 {
      count += 1
    }
  }
  count
}

///|
/// Copy a bit vector and keep its logical length.
pub fn BitVector::copy(self : BitVector) -> BitVector {
  { length: self.length, storage: copy_bytes(self.storage) }
}

///|
/// Compare two bit vectors including their logical lengths.
pub fn BitVector::equal(self : BitVector, other : BitVector) -> Bool {
  self.length == other.length && self.storage == other.storage
}

///|
/// Apply a bitwise OR to two equally sized vectors.
pub fn BitVector::or(
  self : BitVector,
  other : BitVector,
) -> Result[BitVector, ModbusError] {
  if self.length != other.length {
    return Err(InvalidLength)
  }
  let out = self.copy()
  for index in 0..<out.storage.length() {
    out.storage[index] = out.storage[index] | other.storage[index]
  }
  Ok(out)
}

///|
/// Apply a bitwise AND to two equally sized vectors.
pub fn BitVector::bit_and(
  self : BitVector,
  other : BitVector,
) -> Result[BitVector, ModbusError] {
  if self.length != other.length {
    return Err(InvalidLength)
  }
  let out = self.copy()
  for index in 0..<out.storage.length() {
    out.storage[index] = out.storage[index] & other.storage[index]
  }
  Ok(out)
}

///|
/// Invert all logical bits, keeping padding bits clear.
pub fn BitVector::not(self : BitVector) -> BitVector {
  let out = self.copy()
  for index in 0..<out.storage.length() {
    out.storage[index] = 0xFF ^ out.storage[index]
  }
  if out.length % 8 != 0 && out.storage.length() > 0 {
    out.storage[out.storage.length() - 1] = out.storage[out.storage.length() - 1] &
      ((1 << (out.length % 8)).to_byte() - 1)
  }
  out
}

///|
/// Shift logical bits left, dropping values that fall outside the vector.
pub fn BitVector::shift_left(
  self : BitVector,
  distance : Int,
) -> Result[BitVector, ModbusError] {
  if distance < 0 {
    return Err(InvalidQuantity)
  }
  let out = match BitVector::new(self.length) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for index in distance..<self.length {
    match self.get(index - distance) {
      Ok(value) => ignore(out.set(index, value))
      Err(_) => ()
    }
  }
  Ok(out)
}

///|
/// Shift logical bits right, dropping values that fall outside the vector.
pub fn BitVector::shift_right(
  self : BitVector,
  distance : Int,
) -> Result[BitVector, ModbusError] {
  if distance < 0 {
    return Err(InvalidQuantity)
  }
  let out = match BitVector::new(self.length) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if distance < self.length {
    for index in 0..<(self.length - distance) {
      match self.get(index + distance) {
        Ok(value) => ignore(out.set(index, value))
        Err(_) => ()
      }
    }
  }
  Ok(out)
}

///|
/// Pack a range of bits from a vector for a Modbus response.
pub fn BitVector::pack_range(
  self : BitVector,
  start : Int,
  quantity : Int,
) -> Result[Array[Byte], ModbusError] {
  if start < 0 || quantity < 0 || start + quantity > self.length {
    return Err(InvalidAddress)
  }
  let values : Array[Bool] = []
  for index in start..<(start + quantity) {
    values.push(self.get(index).unwrap())
  }
  Ok(pack_bits(values))
}

///|
/// Replace a range of bits from packed input bytes.
pub fn BitVector::unpack_into(
  self : BitVector,
  start : Int,
  quantity : Int,
  bytes : Array[Byte],
) -> Result[Unit, ModbusError] {
  if start < 0 || quantity < 0 || start + quantity > self.length {
    return Err(InvalidAddress)
  }
  let values = match unpack_bits(bytes, quantity) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for index, value in values {
    let _ = self.set(start + index, value)
  }
  Ok(())
}
