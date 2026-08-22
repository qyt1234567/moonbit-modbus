///|
/// Type constraint for a runtime configuration key.
pub(all) enum ConfigKind {
  Text
  Integer
  Boolean
  ModeValue
  ByteSequence
} derive(Debug, Eq)

///|
/// A configuration value represented without a dynamic runtime dependency.
pub(all) enum ConfigValue {
  TextValue(String)
  IntegerValue(Int)
  BooleanValue(Bool)
  ModeValue(Mode)
  ByteSequenceValue(Array[Byte])
} derive(Debug)

///|
pub fn config_kind_name(kind : ConfigKind) -> String {
  match kind {
    Text => "text"
    Integer => "integer"
    Boolean => "boolean"
    ModeValue => "mode"
    ByteSequence => "bytes"
  }
}

///|
pub fn ConfigValue::kind(self : ConfigValue) -> ConfigKind {
  match self {
    TextValue(_) => Text
    IntegerValue(_) => Integer
    BooleanValue(_) => Boolean
    ModeValue(_) => ModeValue
    ByteSequenceValue(_) => ByteSequence
  }
}

///|
pub fn ConfigValue::as_text(self : ConfigValue) -> Result[String, ModbusError] {
  match self {
    TextValue(value) => Ok(value)
    _ => Err(InvalidData)
  }
}

///|
pub fn ConfigValue::as_integer(self : ConfigValue) -> Result[Int, ModbusError] {
  match self {
    IntegerValue(value) => Ok(value)
    _ => Err(InvalidData)
  }
}

///|
pub fn ConfigValue::as_boolean(self : ConfigValue) -> Result[Bool, ModbusError] {
  match self {
    BooleanValue(value) => Ok(value)
    _ => Err(InvalidData)
  }
}

///|
pub fn ConfigValue::as_mode(self : ConfigValue) -> Result[Mode, ModbusError] {
  match self {
    ModeValue(value) => Ok(value)
    _ => Err(InvalidData)
  }
}

///|
pub fn ConfigValue::as_bytes(
  self : ConfigValue,
) -> Result[Array[Byte], ModbusError] {
  match self {
    ByteSequenceValue(value) => Ok(copy_bytes(value))
    _ => Err(InvalidData)
  }
}

///|
pub fn ConfigValue::display(
  self : ConfigValue,
  redact? : Bool = false,
) -> String {
  if redact {
    return "<redacted>"
  }
  match self {
    TextValue(value) => value
    IntegerValue(value) => value.to_string()
    BooleanValue(value) => if value { "true" } else { "false" }
    ModeValue(value) => mode_name(value)
    ByteSequenceValue(value) => bytes_to_hex_string(value)
  }
}

///|
/// A schema entry describing a single configurable field.
pub(all) struct ConfigSpec {
  key : String
  kind : ConfigKind
  required : Bool
  default_value : ConfigValue?
  min_integer : Int?
  max_integer : Int?
  min_length : Int
  max_length : Int
  secret : Bool
  description : String
}

///|
pub fn ConfigSpec::new(
  key : String,
  kind : ConfigKind,
  required? : Bool = false,
  default_value? : ConfigValue,
  min_integer? : Int,
  max_integer? : Int,
  min_length? : Int = 0,
  max_length? : Int = 4096,
  secret? : Bool = false,
  description? : String = "",
) -> Result[ConfigSpec, ModbusError] {
  if key == "" || min_length < 0 || max_length < min_length {
    return Err(InvalidData)
  }
  if min_integer is Some(low) && max_integer is Some(high) && low > high {
    return Err(InvalidData)
  }
  if default_value is Some(value) && value.kind() != kind {
    return Err(InvalidData)
  }
  Ok({
    key,
    kind,
    required,
    default_value,
    min_integer,
    max_integer,
    min_length,
    max_length,
    secret,
    description,
  })
}

///|
pub fn ConfigSpec::key(self : ConfigSpec) -> String {
  self.key
}

///|
pub fn ConfigSpec::kind(self : ConfigSpec) -> ConfigKind {
  self.kind
}

///|
pub fn ConfigSpec::required(self : ConfigSpec) -> Bool {
  self.required
}

///|
pub fn ConfigSpec::default_value(self : ConfigSpec) -> ConfigValue? {
  self.default_value
}

///|
pub fn ConfigSpec::secret(self : ConfigSpec) -> Bool {
  self.secret
}

///|
pub fn ConfigSpec::description(self : ConfigSpec) -> String {
  self.description
}

///|
pub fn ConfigSpec::validate(
  self : ConfigSpec,
  value : ConfigValue,
) -> Result[Unit, ModbusError] {
  if value.kind() != self.kind {
    return Err(InvalidData)
  }
  match value {
    IntegerValue(number) => {
      if self.min_integer is Some(low) && number < low {
        return Err(InvalidData)
      }
      if self.max_integer is Some(high) && number > high {
        return Err(InvalidData)
      }
    }
    TextValue(text) =>
      if text.length() < self.min_length || text.length() > self.max_length {
        return Err(InvalidLength)
      }
    ByteSequenceValue(bytes) =>
      if bytes.length() < self.min_length || bytes.length() > self.max_length {
        return Err(InvalidLength)
      }
    BooleanValue(_) | ModeValue(_) => ()
  }
  Ok(())
}

///|
pub fn ConfigSpec::summary(self : ConfigSpec) -> String {
  self.key +
  " type=" +
  config_kind_name(self.kind) +
  " required=" +
  (if self.required { "true" } else { "false" })
}

///|
/// A collection of configuration specifications.
pub(all) struct ConfigSchema {
  specs : Array[ConfigSpec]
  max_specs : Int
}

///|
pub fn ConfigSchema::new(
  max_specs? : Int = 256,
) -> Result[ConfigSchema, ModbusError] {
  if max_specs < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ specs: [], max_specs })
  }
}

///|
pub fn ConfigSchema::add(
  self : ConfigSchema,
  spec : ConfigSpec,
) -> Result[Unit, ModbusError] {
  if self.specs.length() >= self.max_specs {
    return Err(CapacityExceeded)
  }
  for current in self.specs {
    if current.key() == spec.key() {
      return Err(InvalidData)
    }
  }
  self.specs.push(spec)
  Ok(())
}

///|
pub fn ConfigSchema::length(self : ConfigSchema) -> Int {
  self.specs.length()
}

///|
pub fn ConfigSchema::find(self : ConfigSchema, key : String) -> ConfigSpec? {
  for spec in self.specs {
    if spec.key() == key {
      return Some(spec)
    }
  }
  None
}

///|
pub fn ConfigSchema::get(
  self : ConfigSchema,
  index : Int,
) -> Result[ConfigSpec, ModbusError] {
  if index < 0 || index >= self.specs.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.specs[index])
  }
}

///|
pub fn ConfigSchema::snapshot(self : ConfigSchema) -> Array[ConfigSpec] {
  let result : Array[ConfigSpec] = []
  for spec in self.specs {
    result.push(spec)
  }
  result
}

///|
pub fn ConfigSchema::validate_values(
  self : ConfigSchema,
  values : Array[ConfigEntry],
) -> Result[Unit, ModbusError] {
  for spec in self.specs {
    let mut found = false
    for entry in values {
      if entry.key() == spec.key() {
        found = true
        match spec.validate(entry.value()) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
    }
    if spec.required() && !found && spec.default_value() is None {
      return Err(InvalidData)
    }
  }
  for entry in values {
    if self.find(entry.key()) is None {
      return Err(InvalidData)
    }
  }
  Ok(())
}

///|
/// A key/value pair in a runtime configuration snapshot.
pub(all) struct ConfigEntry {
  key : String
  value : ConfigValue
  source : String
  revision : Int
}

///|
pub fn ConfigEntry::new(
  key : String,
  value : ConfigValue,
  source? : String = "runtime",
  revision? : Int = 0,
) -> Result[ConfigEntry, ModbusError] {
  if key == "" || revision < 0 {
    Err(InvalidData)
  } else {
    Ok({ key, value, source, revision })
  }
}

///|
pub fn ConfigEntry::key(self : ConfigEntry) -> String {
  self.key
}

///|
pub fn ConfigEntry::value(self : ConfigEntry) -> ConfigValue {
  self.value
}

///|
pub fn ConfigEntry::source(self : ConfigEntry) -> String {
  self.source
}

///|
pub fn ConfigEntry::revision(self : ConfigEntry) -> Int {
  self.revision
}

///|
pub fn ConfigEntry::display(
  self : ConfigEntry,
  redact? : Bool = false,
) -> String {
  self.key + "=" + self.value.display(redact~) + " source=" + self.source
}

///|
/// Mutable configuration store with atomic-style patch application.
pub(all) struct RuntimeConfig {
  schema : ConfigSchema
  entries : Array[ConfigEntry]
  mut revision : Int
}

///|
pub fn RuntimeConfig::new(schema : ConfigSchema) -> RuntimeConfig {
  { schema, entries: [], revision: 0 }
}

///|
pub fn RuntimeConfig::revision(self : RuntimeConfig) -> Int {
  self.revision
}

///|
pub fn RuntimeConfig::schema(self : RuntimeConfig) -> ConfigSchema {
  self.schema
}

///|
pub fn RuntimeConfig::length(self : RuntimeConfig) -> Int {
  self.entries.length()
}

///|
pub fn RuntimeConfig::get(self : RuntimeConfig, key : String) -> ConfigValue? {
  for entry in self.entries {
    if entry.key() == key {
      return Some(entry.value())
    }
  }
  match self.schema.find(key) {
    Some(spec) => spec.default_value()
    None => None
  }
}

///|
pub fn RuntimeConfig::entry(self : RuntimeConfig, key : String) -> ConfigEntry? {
  for entry in self.entries {
    if entry.key() == key {
      return Some(entry)
    }
  }
  None
}

///|
pub fn RuntimeConfig::set(
  self : RuntimeConfig,
  key : String,
  value : ConfigValue,
  source? : String = "runtime",
) -> Result[Unit, ModbusError] {
  let spec = match self.schema.find(key) {
    Some(value) => value
    None => return Err(InvalidData)
  }
  match spec.validate(value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let entry = ConfigEntry::new(key, value, source~, revision=self.revision + 1).unwrap()
  for index, current in self.entries {
    if current.key() == key {
      self.entries[index] = entry
      self.revision += 1
      return Ok(())
    }
  }
  self.entries.push(entry)
  self.revision += 1
  Ok(())
}

///|
pub fn RuntimeConfig::remove(
  self : RuntimeConfig,
  key : String,
) -> Result[Unit, ModbusError] {
  for index, entry in self.entries {
    if entry.key() == key {
      ignore(self.entries.remove(index))
      self.revision += 1
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
pub fn RuntimeConfig::validate(
  self : RuntimeConfig,
) -> Result[Unit, ModbusError] {
  self.schema.validate_values(self.entries)
}

///|
pub fn RuntimeConfig::snapshot(self : RuntimeConfig) -> Array[ConfigEntry] {
  let result : Array[ConfigEntry] = []
  for entry in self.entries {
    result.push(entry)
  }
  result
}

///|
pub fn RuntimeConfig::export_lines(
  self : RuntimeConfig,
  redact? : Bool = true,
) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    result.push(entry.display(redact~))
  }
  result
}

///|
/// A change applied to a runtime configuration.
pub(all) enum ConfigOperation {
  SetValue(String, ConfigValue)
  RemoveValue(String)
} derive(Debug)

///|
pub fn RuntimeConfig::apply(
  self : RuntimeConfig,
  operations : Array[ConfigOperation],
  source? : String = "patch",
) -> Result[Int, ModbusError] {
  let before = self.revision
  for operation in operations {
    match operation {
      SetValue(key, value) =>
        match self.set(key, value, source~) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      RemoveValue(key) =>
        match self.remove(key) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
    }
  }
  Ok(self.revision - before)
}

///|
pub fn config_values_equal(left : ConfigValue, right : ConfigValue) -> Bool {
  match (left, right) {
    (TextValue(a), TextValue(b)) => a == b
    (IntegerValue(a), IntegerValue(b)) => a == b
    (BooleanValue(a), BooleanValue(b)) => a == b
    (ModeValue(a), ModeValue(b)) => a == b
    (ByteSequenceValue(a), ByteSequenceValue(b)) => a == b
    _ => false
  }
}

///|
pub fn config_diff(
  before : Array[ConfigEntry],
  after : Array[ConfigEntry],
) -> Array[ConfigOperation] {
  let result : Array[ConfigOperation] = []
  for old in before {
    let mut found = false
    for current in after {
      if current.key() == old.key() {
        found = true
        if !config_values_equal(old.value(), current.value()) {
          result.push(SetValue(current.key(), current.value()))
        }
      }
    }
    if !found {
      result.push(RemoveValue(old.key()))
    }
  }
  for current in after {
    let mut found = false
    for old in before {
      if old.key() == current.key() {
        found = true
      }
    }
    if !found {
      result.push(SetValue(current.key(), current.value()))
    }
  }
  result
}

///|
pub fn config_schema_summary(schema : ConfigSchema) -> String {
  let mut required = 0
  for spec in schema.snapshot() {
    if spec.required() {
      required += 1
    }
  }
  "specs=" + schema.length().to_string() + " required=" + required.to_string()
}
