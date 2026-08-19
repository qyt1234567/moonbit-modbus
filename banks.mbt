///|
/// A contiguous, bounds-checked register bank.
pub(all) struct RegisterBank {
  start : UInt16
  values : Array[UInt16]
  writable : Bool
}

///|
/// Create a register bank in the 16-bit address space.
pub fn RegisterBank::new(
  start : UInt16,
  length : Int,
  writable? : Bool = true,
) -> Result[RegisterBank, ModbusError] {
  if length < 0 || start.to_int() + length > 65536 {
    return Err(CapacityExceeded)
  }
  let values : Array[UInt16] = []
  for _ in 0..<length {
    values.push(0)
  }
  Ok({ start, values, writable })
}

///|
pub fn RegisterBank::start(self : RegisterBank) -> UInt16 {
  self.start
}

///|
pub fn RegisterBank::length(self : RegisterBank) -> Int {
  self.values.length()
}

///|
pub fn RegisterBank::end_exclusive(self : RegisterBank) -> Int {
  self.start.to_int() + self.values.length()
}

///|
pub fn RegisterBank::is_writable(self : RegisterBank) -> Bool {
  self.writable
}

///|
pub fn RegisterBank::contains(
  self : RegisterBank,
  address : UInt16,
  quantity : Int,
) -> Bool {
  quantity >= 0 &&
  address.to_int() >= self.start.to_int() &&
  address.to_int() + quantity <= self.end_exclusive()
}

///|
fn RegisterBank::index(
  self : RegisterBank,
  address : UInt16,
) -> Result[Int, ModbusError] {
  if !self.contains(address, 1) {
    Err(InvalidAddress)
  } else {
    Ok(address.to_int() - self.start.to_int())
  }
}

///|
pub fn RegisterBank::get(
  self : RegisterBank,
  address : UInt16,
) -> Result[UInt16, ModbusError] {
  match self.index(address) {
    Ok(index) => Ok(self.values[index])
    Err(error) => Err(error)
  }
}

///|
pub fn RegisterBank::set(
  self : RegisterBank,
  address : UInt16,
  value : UInt16,
) -> Result[Unit, ModbusError] {
  if !self.writable {
    return Err(Unsupported)
  }
  match self.index(address) {
    Ok(index) => {
      self.values[index] = value
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
pub fn RegisterBank::read(
  self : RegisterBank,
  address : UInt16,
  quantity : Int,
) -> Result[Array[UInt16], ModbusError] {
  if quantity < 1 || quantity > 125 || !self.contains(address, quantity) {
    return Err(InvalidAddress)
  }
  let out : Array[UInt16] = []
  let start = address.to_int() - self.start.to_int()
  for index in start..<(start + quantity) {
    out.push(self.values[index])
  }
  Ok(out)
}

///|
pub fn RegisterBank::write(
  self : RegisterBank,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Unit, ModbusError] {
  if !self.writable {
    return Err(Unsupported)
  }
  if values.length() < 1 ||
    values.length() > 123 ||
    !self.contains(address, values.length()) {
    return Err(InvalidAddress)
  }
  let start = address.to_int() - self.start.to_int()
  for index, value in values {
    self.values[start + index] = value
  }
  Ok(())
}

///|
pub fn RegisterBank::fill(self : RegisterBank, value : UInt16) -> Unit {
  for index in 0..<self.values.length() {
    self.values[index] = value
  }
}

///|
pub fn RegisterBank::clear(self : RegisterBank) -> Unit {
  self.fill(0)
}

///|
pub fn RegisterBank::snapshot(self : RegisterBank) -> Array[UInt16] {
  copy_registers(self.values)
}

///|
pub fn RegisterBank::write_mask(
  self : RegisterBank,
  address : UInt16,
  and_mask : UInt16,
  or_mask : UInt16,
) -> Result[UInt16, ModbusError] {
  let current = match self.get(address) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let next = (current & and_mask) | (or_mask & (and_mask ^ 0xFFFF))
  match self.set(address, next) {
    Ok(_) => Ok(next)
    Err(error) => Err(error)
  }
}

///|
/// A bounded coil/discrete-input bank backed by a bit vector.
pub(all) struct CoilBank {
  start : UInt16
  bits : BitVector
  writable : Bool
}

///|
pub fn CoilBank::new(
  start : UInt16,
  length : Int,
  writable? : Bool = true,
) -> Result[CoilBank, ModbusError] {
  match BitVector::new(length) {
    Ok(bits) => Ok({ start, bits, writable })
    Err(error) => Err(error)
  }
}

///|
pub fn CoilBank::start(self : CoilBank) -> UInt16 {
  self.start
}

///|
pub fn CoilBank::length(self : CoilBank) -> Int {
  self.bits.length()
}

///|
pub fn CoilBank::is_writable(self : CoilBank) -> Bool {
  self.writable
}

///|
pub fn CoilBank::contains(
  self : CoilBank,
  address : UInt16,
  quantity : Int,
) -> Bool {
  quantity >= 0 &&
  address.to_int() >= self.start.to_int() &&
  address.to_int() + quantity <= self.start.to_int() + self.bits.length()
}

///|
pub fn CoilBank::get(
  self : CoilBank,
  address : UInt16,
) -> Result[Bool, ModbusError] {
  if !self.contains(address, 1) {
    Err(InvalidAddress)
  } else {
    self.bits.get(address.to_int() - self.start.to_int())
  }
}

///|
pub fn CoilBank::set(
  self : CoilBank,
  address : UInt16,
  value : Bool,
) -> Result[Unit, ModbusError] {
  if !self.writable {
    return Err(Unsupported)
  }
  if !self.contains(address, 1) {
    Err(InvalidAddress)
  } else {
    self.bits.set(address.to_int() - self.start.to_int(), value)
  }
}

///|
pub fn CoilBank::read(
  self : CoilBank,
  address : UInt16,
  quantity : Int,
) -> Result[Array[Bool], ModbusError] {
  if quantity < 1 || quantity > 2000 || !self.contains(address, quantity) {
    return Err(InvalidAddress)
  }
  let out : Array[Bool] = []
  let start = address.to_int() - self.start.to_int()
  for index in start..<(start + quantity) {
    out.push(self.bits.get(index).unwrap())
  }
  Ok(out)
}

///|
pub fn CoilBank::write(
  self : CoilBank,
  address : UInt16,
  values : Array[Bool],
) -> Result[Unit, ModbusError] {
  if !self.writable {
    return Err(Unsupported)
  }
  if values.length() < 1 ||
    values.length() > 1968 ||
    !self.contains(address, values.length()) {
    return Err(InvalidAddress)
  }
  let start = address.to_int() - self.start.to_int()
  for index, value in values {
    let _ = self.bits.set(start + index, value)
  }
  Ok(())
}

///|
pub fn CoilBank::fill(self : CoilBank, value : Bool) -> Unit {
  self.bits.fill(value)
}

///|
pub fn CoilBank::clear(self : CoilBank) -> Unit {
  self.fill(false)
}

///|
pub fn CoilBank::snapshot(self : CoilBank) -> Array[Bool] {
  self.bits.to_bits()
}

///|
pub fn CoilBank::snapshot_bytes(self : CoilBank) -> Array[Byte] {
  self.bits.to_bytes()
}

///|
/// The four standard Modbus data tables exposed by a device.
pub(all) struct DeviceMemory {
  coils : CoilBank
  discrete_inputs : CoilBank
  input_registers : RegisterBank
  holding_registers : RegisterBank
}

///|
/// Create a device memory map with all tables starting at address zero.
pub fn DeviceMemory::new(
  coil_capacity? : Int = 2000,
  register_capacity? : Int = 125,
) -> Result[DeviceMemory, ModbusError] {
  let coils = match CoilBank::new(0, coil_capacity, writable=true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let discrete_inputs = match CoilBank::new(0, coil_capacity, writable=false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let input_registers = match
    RegisterBank::new(0, register_capacity, writable=false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let holding_registers = match
    RegisterBank::new(0, register_capacity, writable=true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ coils, discrete_inputs, input_registers, holding_registers })
}

///|
pub fn DeviceMemory::coils(self : DeviceMemory) -> CoilBank {
  self.coils
}

///|
pub fn DeviceMemory::discrete_inputs(self : DeviceMemory) -> CoilBank {
  self.discrete_inputs
}

///|
pub fn DeviceMemory::input_registers(self : DeviceMemory) -> RegisterBank {
  self.input_registers
}

///|
pub fn DeviceMemory::holding_registers(self : DeviceMemory) -> RegisterBank {
  self.holding_registers
}

///|
pub fn DeviceMemory::clear(self : DeviceMemory) -> Unit {
  self.coils.clear()
  self.discrete_inputs.clear()
  self.input_registers.clear()
  self.holding_registers.clear()
}

///|
pub fn DeviceMemory::load_holding(
  self : DeviceMemory,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Unit, ModbusError] {
  self.holding_registers.write(address, values)
}

///|
pub fn DeviceMemory::load_input(
  self : DeviceMemory,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Unit, ModbusError] {
  if !self.input_registers.contains(address, values.length()) {
    return Err(InvalidAddress)
  }
  let start = address.to_int() - self.input_registers.start().to_int()
  for index, value in values {
    self.input_registers.values[start + index] = value
  }
  Ok(())
}

///|
pub fn DeviceMemory::load_discrete(
  self : DeviceMemory,
  address : UInt16,
  values : Array[Bool],
) -> Result[Unit, ModbusError] {
  if !self.discrete_inputs.contains(address, values.length()) {
    return Err(InvalidAddress)
  }
  let start = address.to_int() - self.discrete_inputs.start().to_int()
  for index, value in values {
    let _ = self.discrete_inputs.bits.set(start + index, value)
  }
  Ok(())
}
