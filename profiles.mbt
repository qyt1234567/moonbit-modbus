///|
/// A logical address area used by a device profile.
pub(all) enum ProfileArea {
  Coils
  DiscreteInputs
  HoldingRegisters
  InputRegisters
} derive(Debug, Eq)

///|
/// Encoding used when a profile point is mapped to registers.
pub(all) enum ProfileEncoding {
  Bit
  Unsigned16
  Signed16
  Unsigned32
  Signed32
  Unsigned64
  RawWords
} derive(Debug, Eq)

///|
/// A single named data point exposed by an industrial device.
pub(all) struct ProfilePoint {
  id : String
  label : String
  area : ProfileArea
  address : UInt16
  quantity : Int
  encoding : ProfileEncoding
  writable : Bool
  scale_numerator : Int
  scale_denominator : Int
  offset : Int
}

///|
pub fn ProfilePoint::new(
  id : String,
  label : String,
  area : ProfileArea,
  address : UInt16,
  quantity : Int,
  encoding : ProfileEncoding,
  writable? : Bool = false,
  scale_numerator? : Int = 1,
  scale_denominator? : Int = 1,
  offset? : Int = 0,
) -> Result[ProfilePoint, ModbusError] {
  if id == "" || label == "" {
    return Err(InvalidData)
  }
  if quantity < 1 {
    return Err(InvalidQuantity)
  }
  if scale_denominator == 0 {
    return Err(InvalidData)
  }
  if !profile_area_accepts(area, encoding, quantity) {
    return Err(InvalidData)
  }
  if !valid_address_range(address, quantity * profile_words_per_unit(encoding)) {
    return Err(InvalidAddress)
  }
  if writable && !profile_area_writable(area) {
    return Err(Unsupported)
  }
  Ok({
    id,
    label,
    area,
    address,
    quantity,
    encoding,
    writable,
    scale_numerator,
    scale_denominator,
    offset,
  })
}

///|
fn profile_area_writable(area : ProfileArea) -> Bool {
  match area {
    Coils | HoldingRegisters => true
    DiscreteInputs | InputRegisters => false
  }
}

///|
fn profile_words_per_unit(encoding : ProfileEncoding) -> Int {
  match encoding {
    Bit | Unsigned16 | Signed16 => 1
    Unsigned32 | Signed32 => 2
    Unsigned64 => 4
    RawWords => 1
  }
}

///|
fn profile_area_accepts(
  area : ProfileArea,
  encoding : ProfileEncoding,
  quantity : Int,
) -> Bool {
  match area {
    Coils | DiscreteInputs => encoding == Bit && quantity <= 2000
    HoldingRegisters | InputRegisters => encoding != Bit && quantity <= 125
  }
}

///|
pub fn ProfilePoint::id(self : ProfilePoint) -> String {
  self.id
}

///|
pub fn ProfilePoint::label(self : ProfilePoint) -> String {
  self.label
}

///|
pub fn ProfilePoint::area(self : ProfilePoint) -> ProfileArea {
  self.area
}

///|
pub fn ProfilePoint::address(self : ProfilePoint) -> UInt16 {
  self.address
}

///|
pub fn ProfilePoint::quantity(self : ProfilePoint) -> Int {
  self.quantity
}

///|
pub fn ProfilePoint::encoding(self : ProfilePoint) -> ProfileEncoding {
  self.encoding
}

///|
pub fn ProfilePoint::writable(self : ProfilePoint) -> Bool {
  self.writable
}

///|
pub fn ProfilePoint::end_exclusive(self : ProfilePoint) -> Int {
  self.address.to_int() + self.quantity * profile_words_per_unit(self.encoding)
}

///|
pub fn ProfilePoint::register_count(self : ProfilePoint) -> Int {
  self.quantity * profile_words_per_unit(self.encoding)
}

///|
pub fn ProfilePoint::contains(self : ProfilePoint, address : UInt16) -> Bool {
  address.to_int() >= self.address.to_int() &&
  address.to_int() < self.end_exclusive()
}

///|
pub fn ProfilePoint::contains_range(
  self : ProfilePoint,
  address : UInt16,
  length : Int,
) -> Bool {
  length >= 1 &&
  address.to_int() >= self.address.to_int() &&
  address.to_int() + length <= self.end_exclusive()
}

///|
pub fn ProfilePoint::scale_numerator(self : ProfilePoint) -> Int {
  self.scale_numerator
}

///|
pub fn ProfilePoint::scale_denominator(self : ProfilePoint) -> Int {
  self.scale_denominator
}

///|
pub fn ProfilePoint::offset(self : ProfilePoint) -> Int {
  self.offset
}

///|
pub fn ProfilePoint::raw_to_engineering(self : ProfilePoint, raw : Int) -> Int {
  raw * self.scale_numerator / self.scale_denominator + self.offset
}

///|
pub fn ProfilePoint::engineering_to_raw(
  self : ProfilePoint,
  value : Int,
) -> Result[Int, ModbusError] {
  if self.scale_numerator == 0 {
    return Err(InvalidData)
  }
  Ok((value - self.offset) * self.scale_denominator / self.scale_numerator)
}

///|
pub fn ProfilePoint::function_code(self : ProfilePoint) -> Byte {
  match self.area {
    Coils => 1
    DiscreteInputs => 2
    HoldingRegisters => 3
    InputRegisters => 4
  }
}

///|
pub fn ProfilePoint::read_request(
  self : ProfilePoint,
  unit_id : Byte,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  let address = self.address
  let quantity = self.register_count()
  match self.area {
    Coils => read_coils(unit_id, address, self.quantity.to_uint16())
    DiscreteInputs =>
      read_discrete_inputs(unit_id, address, self.quantity.to_uint16())
    HoldingRegisters => Ok(read_holding(unit_id, address, quantity.to_uint16()))
    InputRegisters =>
      read_input_registers(unit_id, address, quantity.to_uint16())
  }
}

///|
pub fn ProfilePoint::write_request(
  self : ProfilePoint,
  unit_id : Byte,
  value : Int,
) -> Result[Frame, ModbusError] {
  if !self.writable {
    return Err(Unsupported)
  }
  if !is_valid_unit_id(unit_id, broadcast=false) {
    return Err(InvalidUnitId)
  }
  match self.area {
    Coils => write_single_coil(unit_id, self.address, value != 0)
    HoldingRegisters => {
      let raw = match self.engineering_to_raw(value) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if raw < 0 || raw > 65535 {
        Err(InvalidData)
      } else {
        write_single_register_checked(unit_id, self.address, raw.to_uint16())
      }
    }
    DiscreteInputs | InputRegisters => Err(Unsupported)
  }
}

///|
pub fn ProfilePoint::summary(self : ProfilePoint) -> String {
  self.id +
  "=" +
  profile_area_name(self.area) +
  "@" +
  self.address.to_string() +
  "/" +
  self.quantity.to_string() +
  " writable=" +
  (if self.writable { "true" } else { "false" })
}

///|
pub fn profile_area_name(area : ProfileArea) -> String {
  match area {
    Coils => "coils"
    DiscreteInputs => "discrete-inputs"
    HoldingRegisters => "holding-registers"
    InputRegisters => "input-registers"
  }
}

///|
pub fn profile_encoding_name(encoding : ProfileEncoding) -> String {
  match encoding {
    Bit => "bit"
    Unsigned16 => "u16"
    Signed16 => "i16"
    Unsigned32 => "u32"
    Signed32 => "i32"
    Unsigned64 => "u64"
    RawWords => "words"
  }
}

///|
/// A named set of points belonging to one device model.
pub(all) struct DeviceProfile {
  name : String
  model : String
  unit_id : Byte
  revision : String
  points : Array[ProfilePoint]
  max_points : Int
}

///|
pub fn DeviceProfile::new(
  name : String,
  model : String,
  unit_id : Byte,
  revision? : String = "1",
  max_points? : Int = 512,
) -> Result[DeviceProfile, ModbusError] {
  if name == "" || model == "" || revision == "" {
    return Err(InvalidData)
  }
  if !is_valid_unit_id(unit_id, broadcast=false) || max_points < 1 {
    return Err(InvalidUnitId)
  }
  Ok({ name, model, unit_id, revision, points: [], max_points })
}

///|
pub fn DeviceProfile::name(self : DeviceProfile) -> String {
  self.name
}

///|
pub fn DeviceProfile::model(self : DeviceProfile) -> String {
  self.model
}

///|
pub fn DeviceProfile::unit_id(self : DeviceProfile) -> Byte {
  self.unit_id
}

///|
pub fn DeviceProfile::revision(self : DeviceProfile) -> String {
  self.revision
}

///|
pub fn DeviceProfile::point_count(self : DeviceProfile) -> Int {
  self.points.length()
}

///|
pub fn DeviceProfile::add_point(
  self : DeviceProfile,
  point : ProfilePoint,
) -> Result[Unit, ModbusError] {
  if self.points.length() >= self.max_points {
    return Err(CapacityExceeded)
  }
  if point.writable() && point.area() == DiscreteInputs {
    return Err(Unsupported)
  }
  for current in self.points {
    if current.id() == point.id() {
      return Err(InvalidData)
    }
    if current.area() == point.area() &&
      current.contains_range(point.address(), point.register_count()) {
      return Err(InvalidAddress)
    }
  }
  self.points.push(point)
  Ok(())
}

///|
pub fn DeviceProfile::remove_point(
  self : DeviceProfile,
  id : String,
) -> Result[ProfilePoint, ModbusError] {
  for index, point in self.points {
    if point.id() == id {
      ignore(self.points.remove(index))
      return Ok(point)
    }
  }
  Err(InvalidData)
}

///|
pub fn DeviceProfile::find(self : DeviceProfile, id : String) -> ProfilePoint? {
  for point in self.points {
    if point.id() == id {
      return Some(point)
    }
  }
  None
}

///|
pub fn DeviceProfile::point(
  self : DeviceProfile,
  index : Int,
) -> Result[ProfilePoint, ModbusError] {
  if index < 0 || index >= self.points.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.points[index])
  }
}

///|
pub fn DeviceProfile::points(self : DeviceProfile) -> Array[ProfilePoint] {
  let result : Array[ProfilePoint] = []
  for point in self.points {
    result.push(point)
  }
  result
}

///|
pub fn DeviceProfile::points_in_area(
  self : DeviceProfile,
  area : ProfileArea,
) -> Array[ProfilePoint] {
  let result : Array[ProfilePoint] = []
  for point in self.points {
    if point.area() == area {
      result.push(point)
    }
  }
  result
}

///|
pub fn DeviceProfile::writable_points(
  self : DeviceProfile,
) -> Array[ProfilePoint] {
  let result : Array[ProfilePoint] = []
  for point in self.points {
    if point.writable() {
      result.push(point)
    }
  }
  result
}

///|
pub fn DeviceProfile::read_requests(
  self : DeviceProfile,
) -> Result[Array[Frame], ModbusError] {
  let result : Array[Frame] = []
  for point in self.points {
    match point.read_request(self.unit_id) {
      Ok(frame) => result.push(frame)
      Err(error) => return Err(error)
    }
  }
  Ok(result)
}

///|
pub fn DeviceProfile::validate(
  self : DeviceProfile,
) -> Result[Unit, ModbusError] {
  if self.points.length() == 0 {
    return Err(InvalidData)
  }
  for point in self.points {
    if point.id() == "" ||
      point.quantity() < 1 ||
      !valid_address_range(point.address(), point.register_count()) {
      return Err(InvalidData)
    }
  }
  Ok(())
}

///|
pub fn DeviceProfile::summary(self : DeviceProfile) -> String {
  self.name +
  " model=" +
  self.model +
  " unit=" +
  self.unit_id.to_string() +
  " revision=" +
  self.revision +
  " points=" +
  self.points.length().to_string()
}

///|
/// Registry for profiles loaded from an application configuration.
pub(all) struct ProfileRegistry {
  profiles : Array[DeviceProfile]
  max_profiles : Int
}

///|
pub fn ProfileRegistry::new(
  max_profiles? : Int = 64,
) -> Result[ProfileRegistry, ModbusError] {
  if max_profiles < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ profiles: [], max_profiles })
  }
}

///|
pub fn ProfileRegistry::count(self : ProfileRegistry) -> Int {
  self.profiles.length()
}

///|
pub fn ProfileRegistry::add(
  self : ProfileRegistry,
  profile : DeviceProfile,
) -> Result[Unit, ModbusError] {
  match profile.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for current in self.profiles {
    if current.name() == profile.name() ||
      current.unit_id() == profile.unit_id() {
      return Err(InvalidData)
    }
  }
  if self.profiles.length() >= self.max_profiles {
    return Err(CapacityExceeded)
  }
  self.profiles.push(profile)
  Ok(())
}

///|
pub fn ProfileRegistry::replace(
  self : ProfileRegistry,
  profile : DeviceProfile,
) -> Result[Unit, ModbusError] {
  match profile.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for index, current in self.profiles {
    if current.name() == profile.name() {
      self.profiles[index] = profile
      return Ok(())
    }
  }
  self.add(profile)
}

///|
pub fn ProfileRegistry::by_name(
  self : ProfileRegistry,
  name : String,
) -> DeviceProfile? {
  for profile in self.profiles {
    if profile.name() == name {
      return Some(profile)
    }
  }
  None
}

///|
pub fn ProfileRegistry::by_unit(
  self : ProfileRegistry,
  unit_id : Byte,
) -> DeviceProfile? {
  for profile in self.profiles {
    if profile.unit_id() == unit_id {
      return Some(profile)
    }
  }
  None
}

///|
pub fn ProfileRegistry::snapshot(
  self : ProfileRegistry,
) -> Array[DeviceProfile] {
  let result : Array[DeviceProfile] = []
  for profile in self.profiles {
    result.push(profile)
  }
  result
}

///|
pub fn ProfileRegistry::remove_by_name(
  self : ProfileRegistry,
  name : String,
) -> Result[DeviceProfile, ModbusError] {
  for index, profile in self.profiles {
    if profile.name() == name {
      ignore(self.profiles.remove(index))
      return Ok(profile)
    }
  }
  Err(InvalidData)
}

///|
/// Return all points that are safe to poll in one contiguous register range.
pub fn profile_contiguous_points(
  points : Array[ProfilePoint],
  area : ProfileArea,
) -> Array[ProfilePoint] {
  let result : Array[ProfilePoint] = []
  let mut next_address = 0
  let mut started = false
  for point in points {
    if point.area() == area {
      if !started || point.address().to_int() == next_address {
        result.push(point)
        next_address = point.end_exclusive()
        started = true
      }
    }
  }
  result
}

///|
pub fn profile_point_value_from_registers(
  point : ProfilePoint,
  registers : Array[UInt16],
) -> Result[ProfileValue, ModbusError] {
  if point.area() == Coils || point.area() == DiscreteInputs {
    return Err(InvalidData)
  }
  if registers.length() != point.register_count() {
    return Err(InvalidLength)
  }
  match point.encoding() {
    Unsigned16 => Ok(U16(registers[0]))
    Signed16 => Ok(I16(signed_register(registers[0])))
    Unsigned32 =>
      Ok(U32((registers[0].to_uint() << 16) | registers[1].to_uint()))
    Signed32 =>
      Ok(
        I32(
          ((registers[0].to_uint() << 16) | registers[1].to_uint()).reinterpret_as_int(),
        ),
      )
    Unsigned64 => {
      let mut value : UInt64 = 0
      for register in registers {
        value = (value << 16) | register.to_uint64()
      }
      Ok(U64(value))
    }
    RawWords => Ok(Words(registers))
    Bit => Err(InvalidData)
  }
}

///|
/// A typed value returned by a profile point decoder.
pub(all) enum ProfileValue {
  BitValue(Bool)
  U16(UInt16)
  I16(Int)
  U32(UInt)
  I32(Int)
  U64(UInt64)
  Words(Array[UInt16])
} derive(Debug)

///|
pub fn ProfileValue::as_int(self : ProfileValue) -> Result[Int, ModbusError] {
  match self {
    BitValue(value) => Ok(if value { 1 } else { 0 })
    U16(value) => Ok(value.to_int())
    I16(value) => Ok(value)
    U32(value) =>
      if value > 2147483647 {
        Err(InvalidData)
      } else {
        Ok(value.reinterpret_as_int())
      }
    I32(value) => Ok(value)
    U64(_) => Err(InvalidData)
    Words(_) => Err(InvalidData)
  }
}

///|
pub fn ProfileValue::word_count(self : ProfileValue) -> Int {
  match self {
    BitValue(_) | U16(_) | I16(_) => 1
    U32(_) | I32(_) => 2
    U64(_) => 4
    Words(values) => values.length()
  }
}

///|
pub fn ProfileValue::summary(self : ProfileValue) -> String {
  match self {
    BitValue(value) => "bit=" + (if value { "true" } else { "false" })
    U16(value) => "u16=" + value.to_string()
    I16(value) => "i16=" + value.to_string()
    U32(value) => "u32=" + value.to_string()
    I32(value) => "i32=" + value.to_string()
    U64(value) => "u64=" + value.to_string()
    Words(values) => "words=" + values.length().to_string()
  }
}
