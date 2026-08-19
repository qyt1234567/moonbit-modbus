///|
/// Typed interpretation for a register-backed device schema.
pub(all) enum RegisterFieldKind {
  Unsigned16
  Signed16
  Unsigned32
  Signed32
  Float32
  Unsigned64
  BitField(Int)
} derive(Debug, Eq)

///|
pub fn RegisterFieldKind::width(self : RegisterFieldKind) -> Int {
  match self {
    Unsigned16 | Signed16 => 1
    Unsigned32 | Signed32 | Float32 => 2
    Unsigned64 => 4
    BitField(bits) => (bits + 15) / 16
  }
}

///|
pub fn RegisterFieldKind::name(self : RegisterFieldKind) -> String {
  match self {
    Unsigned16 => "u16"
    Signed16 => "i16"
    Unsigned32 => "u32"
    Signed32 => "i32"
    Float32 => "f32"
    Unsigned64 => "u64"
    BitField(_) => "bit-field"
  }
}

///|
/// A value returned by schema-aware reads.
pub(all) enum RegisterValue {
  U16(UInt16)
  I16(Int)
  U32(UInt)
  I32(Int)
  F32(Float)
  U64(UInt64)
  Bits(Array[Bool])
}

///|
/// A named register field with an explicit wire representation.
pub(all) struct RegisterField {
  name : String
  address : UInt16
  kind : RegisterFieldKind
  writable : Bool
  scale : Float
}

///|
pub fn RegisterField::new(
  name : String,
  address : UInt16,
  kind : RegisterFieldKind,
  writable? : Bool = false,
  scale? : Float = 1.0,
) -> Result[RegisterField, ModbusError] {
  if name.length() == 0 ||
    !valid_address_range(address, kind.width()) ||
    scale == 0.0 {
    Err(InvalidData)
  } else {
    Ok({ name, address, kind, writable, scale })
  }
}

///|
pub fn RegisterField::name(self : RegisterField) -> String {
  self.name
}

///|
pub fn RegisterField::address(self : RegisterField) -> UInt16 {
  self.address
}

///|
pub fn RegisterField::kind(self : RegisterField) -> RegisterFieldKind {
  self.kind
}

///|
pub fn RegisterField::width(self : RegisterField) -> Int {
  self.kind.width()
}

///|
pub fn RegisterField::is_writable(self : RegisterField) -> Bool {
  self.writable
}

///|
pub fn RegisterField::scale(self : RegisterField) -> Float {
  self.scale
}

///|
/// A schema with unique named fields and no overlapping wire ranges.
pub struct RegisterSchema {
  fields : Array[RegisterField]
  max_fields : Int
}

///|
pub fn RegisterSchema::new(
  max_fields? : Int = 256,
) -> Result[RegisterSchema, ModbusError] {
  if max_fields < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ fields: [], max_fields })
  }
}

///|
pub fn RegisterSchema::add(
  self : RegisterSchema,
  field : RegisterField,
) -> Result[Unit, ModbusError] {
  if self.fields.length() >= self.max_fields {
    return Err(CapacityExceeded)
  }
  for existing in self.fields {
    if existing.name == field.name {
      return Err(InvalidData)
    }
    if ranges_overlap(
        existing.address.to_int(),
        existing.width(),
        field.address.to_int(),
        field.width(),
      ) {
      return Err(InvalidAddress)
    }
  }
  self.fields.push(field)
  Ok(())
}

///|
fn ranges_overlap(a : Int, a_width : Int, b : Int, b_width : Int) -> Bool {
  a < b + b_width && b < a + a_width
}

///|
pub fn RegisterSchema::length(self : RegisterSchema) -> Int {
  self.fields.length()
}

///|
pub fn RegisterSchema::field(
  self : RegisterSchema,
  name : String,
) -> RegisterField? {
  for field in self.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
pub fn RegisterSchema::fields(self : RegisterSchema) -> Array[RegisterField] {
  let out : Array[RegisterField] = []
  for field in self.fields {
    out.push(field)
  }
  out
}

///|
/// Decode one schema field from a register bank.
pub fn RegisterSchema::read(
  self : RegisterSchema,
  name : String,
  bank : RegisterBank,
) -> Result[RegisterValue, ModbusError] {
  let field = match self.field(name) {
    Some(value) => value
    None => return Err(InvalidAddress)
  }
  let values = match bank.read(field.address, field.width()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  decode_field(field, values)
}

///|
fn decode_field(
  field : RegisterField,
  values : Array[UInt16],
) -> Result[RegisterValue, ModbusError] {
  match field.kind {
    Unsigned16 => Ok(U16(values[0]))
    Signed16 => Ok(I16(signed_register(values[0])))
    Unsigned32 =>
      match registers_to_u32(values, HighWordFirst) {
        Ok(value) => Ok(U32(value))
        Err(error) => Err(error)
      }
    Signed32 =>
      match registers_to_i32(values, HighWordFirst) {
        Ok(value) => Ok(I32(value))
        Err(error) => Err(error)
      }
    Float32 =>
      match registers_to_f32(values, HighWordFirst) {
        Ok(value) => Ok(F32(value))
        Err(error) => Err(error)
      }
    Unsigned64 =>
      match registers_to_u64(values, HighWordFirst) {
        Ok(value) => Ok(U64(value))
        Err(error) => Err(error)
      }
    BitField(bits) => {
      let out : Array[Bool] = []
      for index in 0..<bits {
        let word = values[index / 16]
        out.push((word & (1 << (index % 16)).to_uint16()) != 0)
      }
      Ok(Bits(out))
    }
  }
}

///|
/// Encode a typed value and write it to a schema field.
pub fn RegisterSchema::write(
  self : RegisterSchema,
  name : String,
  value : RegisterValue,
  bank : RegisterBank,
) -> Result[Unit, ModbusError] {
  let field = match self.field(name) {
    Some(value) => value
    None => return Err(InvalidAddress)
  }
  if !field.writable {
    return Err(Unsupported)
  }
  let values = match encode_field(field, value) {
    Ok(encoded) => encoded
    Err(error) => return Err(error)
  }
  bank.write(field.address, values)
}

///|
fn encode_field(
  field : RegisterField,
  value : RegisterValue,
) -> Result[Array[UInt16], ModbusError] {
  match (field.kind, value) {
    (Unsigned16, U16(value)) => Ok([value])
    (Signed16, I16(value)) => Ok([value.to_uint16()])
    (Unsigned32, U32(value)) => Ok(u32_to_registers(value, HighWordFirst))
    (Signed32, I32(value)) => Ok(i32_to_registers(value, HighWordFirst))
    (Float32, F32(value)) => Ok(f32_to_registers(value, HighWordFirst))
    (Unsigned64, U64(value)) => Ok(u64_to_registers(value, HighWordFirst))
    (BitField(bits), Bits(values)) => {
      if values.length() != bits {
        return Err(InvalidLength)
      }
      let words : Array[UInt16] = []
      for _ in 0..<((bits + 15) / 16) {
        words.push(0)
      }
      for index, bit in values {
        if bit {
          words[index / 16] = words[index / 16] |
            (1 << (index % 16)).to_uint16()
        }
      }
      Ok(words)
    }
    _ => Err(InvalidData)
  }
}

///|
/// Return the values of every field that fits in a bank snapshot.
pub fn RegisterSchema::read_all(
  self : RegisterSchema,
  bank : RegisterBank,
) -> Result[Array[(String, RegisterValue)], ModbusError] {
  let out : Array[(String, RegisterValue)] = []
  for field in self.fields {
    match bank.read(field.address, field.width()) {
      Ok(values) =>
        match decode_field(field, values) {
          Ok(value) => out.push((field.name, value))
          Err(error) => return Err(error)
        }
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
/// Validate a schema against a register bank before starting a service.
pub fn RegisterSchema::validate_against(
  self : RegisterSchema,
  bank : RegisterBank,
) -> Result[Unit, ModbusError] {
  for field in self.fields {
    if !bank.contains(field.address, field.width()) {
      return Err(InvalidAddress)
    }
    if field.writable && !bank.is_writable() {
      return Err(Unsupported)
    }
  }
  Ok(())
}

///|
/// Render a typed value as a compact diagnostic string.
pub fn register_value_name(value : RegisterValue) -> String {
  match value {
    U16(value) => "u16:" + value.to_string()
    I16(value) => "i16:" + value.to_string()
    U32(value) => "u32:" + value.to_string()
    I32(value) => "i32:" + value.to_string()
    F32(value) => "f32:" + value.to_string()
    U64(value) => "u64:" + value.to_string()
    Bits(values) => "bits:" + values.length().to_string()
  }
}
