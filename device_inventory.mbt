///|
/// Lifecycle state of an enrolled industrial device.
pub(all) enum InventoryState {
  InventoryDiscovered
  InventoryProvisioned
  InventoryOnline
  InventoryOffline
  InventoryRetired
} derive(Debug, Eq)

///|
/// Firmware and identity metadata used by fleet operations.
pub(all) struct InventoryDevice {
  id : String
  label : String
  vendor : String
  model : String
  serial : String
  firmware : String
  unit_id : Byte
  transport : String
  mut state : InventoryState
  mut last_seen : Int?
  tags : Array[String]
}

///|
pub fn InventoryDevice::new(
  id : String,
  label : String,
  vendor : String,
  model : String,
  serial : String,
  firmware : String,
  unit_id : Byte,
  transport : String,
) -> Result[InventoryDevice, ModbusError] {
  if id == "" ||
    label == "" ||
    vendor == "" ||
    model == "" ||
    serial == "" ||
    firmware == "" ||
    transport == "" {
    return Err(InvalidData)
  }
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  Ok({
    id,
    label,
    vendor,
    model,
    serial,
    firmware,
    unit_id,
    transport,
    state: InventoryDiscovered,
    last_seen: None,
    tags: [],
  })
}

///|
pub fn InventoryDevice::id(self : InventoryDevice) -> String {
  self.id
}

///|
pub fn InventoryDevice::label(self : InventoryDevice) -> String {
  self.label
}

///|
pub fn InventoryDevice::vendor(self : InventoryDevice) -> String {
  self.vendor
}

///|
pub fn InventoryDevice::model(self : InventoryDevice) -> String {
  self.model
}

///|
pub fn InventoryDevice::serial(self : InventoryDevice) -> String {
  self.serial
}

///|
pub fn InventoryDevice::firmware(self : InventoryDevice) -> String {
  self.firmware
}

///|
pub fn InventoryDevice::unit_id(self : InventoryDevice) -> Byte {
  self.unit_id
}

///|
pub fn InventoryDevice::transport(self : InventoryDevice) -> String {
  self.transport
}

///|
pub fn InventoryDevice::state(self : InventoryDevice) -> InventoryState {
  self.state
}

///|
pub fn InventoryDevice::last_seen(self : InventoryDevice) -> Int? {
  self.last_seen
}

///|
pub fn InventoryDevice::set_state(
  self : InventoryDevice,
  state : InventoryState,
) -> Unit {
  self.state = state
}

///|
pub fn InventoryDevice::add_tag(
  self : InventoryDevice,
  tag : String,
) -> Result[Unit, ModbusError] {
  if tag == "" {
    return Err(InvalidData)
  }
  for existing in self.tags {
    if existing == tag {
      return Ok(())
    }
  }
  self.tags.push(tag)
  Ok(())
}

///|
pub fn InventoryDevice::has_tag(self : InventoryDevice, tag : String) -> Bool {
  for existing in self.tags {
    if existing == tag {
      return true
    }
  }
  false
}

///|
pub fn InventoryDevice::mark_seen(
  self : InventoryDevice,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  self.last_seen = Some(timestamp)
  self.state = InventoryOnline
  Ok(())
}

///|
pub fn InventoryDevice::stale(
  self : InventoryDevice,
  now : Int,
  timeout : Int,
) -> Result[Bool, ModbusError] {
  if now < 0 || timeout < 1 {
    return Err(InvalidData)
  }
  match self.last_seen {
    Some(timestamp) => Ok(now - timestamp > timeout)
    None => Ok(true)
  }
}

///|
pub fn inventory_state_name(state : InventoryState) -> String {
  match state {
    InventoryDiscovered => "discovered"
    InventoryProvisioned => "provisioned"
    InventoryOnline => "online"
    InventoryOffline => "offline"
    InventoryRetired => "retired"
  }
}

///|
/// A fleet inventory with lookup and stale-device reporting.
pub(all) struct DeviceInventory {
  devices : Array[InventoryDevice]
  max_devices : Int
  mut revision : Int
}

///|
pub fn DeviceInventory::new(
  max_devices? : Int = 4096,
) -> Result[DeviceInventory, ModbusError] {
  if max_devices < 1 {
    Err(InvalidData)
  } else {
    Ok({ devices: [], max_devices, revision: 0 })
  }
}

///|
pub fn DeviceInventory::count(self : DeviceInventory) -> Int {
  self.devices.length()
}

///|
pub fn DeviceInventory::revision(self : DeviceInventory) -> Int {
  self.revision
}

///|
pub fn DeviceInventory::add(
  self : DeviceInventory,
  device : InventoryDevice,
) -> Result[Unit, ModbusError] {
  if self.devices.length() >= self.max_devices {
    return Err(CapacityExceeded)
  }
  for existing in self.devices {
    if existing.id() == device.id() || existing.serial() == device.serial() {
      return Err(InvalidData)
    }
  }
  self.devices.push(device)
  self.revision += 1
  Ok(())
}

///|
pub fn DeviceInventory::get(
  self : DeviceInventory,
  id : String,
) -> InventoryDevice? {
  for device in self.devices {
    if device.id() == id {
      return Some(device)
    }
  }
  None
}

///|
pub fn DeviceInventory::remove(
  self : DeviceInventory,
  id : String,
) -> Result[InventoryDevice, ModbusError] {
  for i in 0..<self.devices.length() {
    if self.devices[i].id() == id {
      self.revision += 1
      return Ok(self.devices.remove(i))
    }
  }
  Err(InvalidData)
}

///|
pub fn DeviceInventory::by_vendor(
  self : DeviceInventory,
  vendor : String,
) -> Array[String] {
  let result : Array[String] = []
  for device in self.devices {
    if device.vendor() == vendor {
      result.push(device.id())
    }
  }
  result
}

///|
pub fn DeviceInventory::by_tag(
  self : DeviceInventory,
  tag : String,
) -> Array[String] {
  let result : Array[String] = []
  for device in self.devices {
    if device.has_tag(tag) {
      result.push(device.id())
    }
  }
  result
}

///|
/// Mark devices stale or offline using one common fleet timestamp.
pub fn DeviceInventory::mark_stale(
  self : DeviceInventory,
  now : Int,
  timeout : Int,
) -> Result[Int, ModbusError] {
  if now < 0 || timeout < 1 {
    return Err(InvalidData)
  }
  let mut count = 0
  for device in self.devices {
    match device.stale(now, timeout) {
      Err(error) => return Err(error)
      Ok(false) => ()
      Ok(true) => {
        device.set_state(InventoryOffline)
        count += 1
      }
    }
  }
  Ok(count)
}

///|
/// Return devices by lifecycle state.
pub fn DeviceInventory::by_state(
  self : DeviceInventory,
  state : InventoryState,
) -> Array[String] {
  let result : Array[String] = []
  for device in self.devices {
    if device.state() == state {
      result.push(device.id())
    }
  }
  result
}

///|
/// Stable tabular export for provisioning and support tools.
pub fn DeviceInventory::export_lines(self : DeviceInventory) -> Array[String] {
  let lines : Array[String] = []
  for device in self.devices {
    lines.push(
      device.id() +
      "\t" +
      device.serial() +
      "\t" +
      device.vendor() +
      "\t" +
      device.model() +
      "\tunit=" +
      device.unit_id().to_int().to_string() +
      "\ttransport=" +
      device.transport() +
      "\tstate=" +
      inventory_state_name(device.state()),
    )
  }
  lines
}

///|
/// A small firmware compatibility constraint.
pub(all) struct FirmwareConstraint {
  vendor : String
  model : String
  minimum : String
  recommended : String
}

///|
pub fn FirmwareConstraint::new(
  vendor : String,
  model : String,
  minimum : String,
  recommended : String,
) -> Result[FirmwareConstraint, ModbusError] {
  if vendor == "" || model == "" || minimum == "" || recommended == "" {
    Err(InvalidData)
  } else {
    Ok({ vendor, model, minimum, recommended })
  }
}

///|
pub fn FirmwareConstraint::matches(
  self : FirmwareConstraint,
  device : InventoryDevice,
) -> Bool {
  device.vendor() == self.vendor && device.model() == self.model
}

///|
pub fn FirmwareConstraint::minimum(self : FirmwareConstraint) -> String {
  self.minimum
}

///|
pub fn FirmwareConstraint::recommended(self : FirmwareConstraint) -> String {
  self.recommended
}
