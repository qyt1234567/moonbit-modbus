///|
/// Lifecycle of an application service attached to a device.
pub(all) enum DeviceServiceState {
  ServiceCreated
  ServiceStarting
  ServiceRunning
  ServiceDraining
  ServiceStopped
  ServiceFailed
} derive(Debug, Eq)

///|
/// Kind of service hosted by the integration layer.
pub(all) enum DeviceServiceKind {
  PollingService
  CommandService
  AlarmService
  HistorianService
  GatewayService
  DiagnosticsService
} derive(Debug, Eq)

///|
/// Registration record for a long-lived device-facing service.
pub(all) struct DeviceService {
  id : String
  device_id : String
  kind : DeviceServiceKind
  endpoint : String
  mut state : DeviceServiceState
  mut started_at : Int?
  mut stopped_at : Int?
  mut restart_count : Int
  tags : Array[String]
}

///|
pub fn DeviceService::new(
  id : String,
  device_id : String,
  kind : DeviceServiceKind,
  endpoint : String,
) -> Result[DeviceService, ModbusError] {
  if id == "" || device_id == "" || endpoint == "" {
    return Err(InvalidData)
  }
  Ok({
    id,
    device_id,
    kind,
    endpoint,
    state: ServiceCreated,
    started_at: None,
    stopped_at: None,
    restart_count: 0,
    tags: [],
  })
}

///|
pub fn DeviceService::id(self : DeviceService) -> String {
  self.id
}

///|
pub fn DeviceService::device_id(self : DeviceService) -> String {
  self.device_id
}

///|
pub fn DeviceService::kind(self : DeviceService) -> DeviceServiceKind {
  self.kind
}

///|
pub fn DeviceService::endpoint(self : DeviceService) -> String {
  self.endpoint
}

///|
pub fn DeviceService::state(self : DeviceService) -> DeviceServiceState {
  self.state
}

///|
pub fn DeviceService::started_at(self : DeviceService) -> Int? {
  self.started_at
}

///|
pub fn DeviceService::stopped_at(self : DeviceService) -> Int? {
  self.stopped_at
}

///|
pub fn DeviceService::restart_count(self : DeviceService) -> Int {
  self.restart_count
}

///|
pub fn DeviceService::tag_count(self : DeviceService) -> Int {
  self.tags.length()
}

///|
pub fn DeviceService::add_tag(
  self : DeviceService,
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
pub fn DeviceService::start(
  self : DeviceService,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 ||
    self.state == ServiceRunning ||
    self.state == ServiceStarting {
    return Err(Busy)
  }
  self.state = ServiceStarting
  self.started_at = Some(timestamp)
  self.stopped_at = None
  self.state = ServiceRunning
  Ok(())
}

///|
pub fn DeviceService::drain(self : DeviceService) -> Result[Unit, ModbusError] {
  if self.state != ServiceRunning {
    return Err(Busy)
  }
  self.state = ServiceDraining
  Ok(())
}

///|
pub fn DeviceService::stop(
  self : DeviceService,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 ||
    self.state == ServiceStopped ||
    self.state == ServiceCreated {
    return Err(Busy)
  }
  self.state = ServiceStopped
  self.stopped_at = Some(timestamp)
  Ok(())
}

///|
pub fn DeviceService::fail(
  self : DeviceService,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  self.state = ServiceFailed
  self.stopped_at = Some(timestamp)
  Ok(())
}

///|
pub fn DeviceService::restart(
  self : DeviceService,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 || self.state == ServiceRunning {
    return Err(Busy)
  }
  self.restart_count += 1
  self.start(timestamp)
}

///|
pub fn device_service_kind_name(kind : DeviceServiceKind) -> String {
  match kind {
    PollingService => "polling"
    CommandService => "command"
    AlarmService => "alarm"
    HistorianService => "historian"
    GatewayService => "gateway"
    DiagnosticsService => "diagnostics"
  }
}

///|
pub fn device_service_state_name(state : DeviceServiceState) -> String {
  match state {
    ServiceCreated => "created"
    ServiceStarting => "starting"
    ServiceRunning => "running"
    ServiceDraining => "draining"
    ServiceStopped => "stopped"
    ServiceFailed => "failed"
  }
}

///|
/// A point/value pair captured from a device snapshot.
pub(all) struct SnapshotValue {
  point_id : String
  value : Int
  quality : ReadingQuality
  timestamp : Int
}

///|
pub fn SnapshotValue::new(
  point_id : String,
  value : Int,
  timestamp : Int,
  quality? : ReadingQuality = Good,
) -> Result[SnapshotValue, ModbusError] {
  if point_id == "" || timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ point_id, value, quality, timestamp })
  }
}

///|
pub fn SnapshotValue::point_id(self : SnapshotValue) -> String {
  self.point_id
}

///|
pub fn SnapshotValue::value(self : SnapshotValue) -> Int {
  self.value
}

///|
pub fn SnapshotValue::quality(self : SnapshotValue) -> ReadingQuality {
  self.quality
}

///|
pub fn SnapshotValue::timestamp(self : SnapshotValue) -> Int {
  self.timestamp
}

///|
pub fn SnapshotValue::is_good(self : SnapshotValue) -> Bool {
  self.quality == Good
}

///|
/// A consistent set of point values from one acquisition cycle.
pub(all) struct DeviceSnapshot {
  device_id : String
  captured_at : Int
  values : Array[SnapshotValue]
  sequence : Int
  mut complete : Bool
}

///|
pub fn DeviceSnapshot::new(
  device_id : String,
  captured_at : Int,
  sequence : Int,
) -> Result[DeviceSnapshot, ModbusError] {
  if device_id == "" || captured_at < 0 || sequence < 1 {
    Err(InvalidData)
  } else {
    Ok({ device_id, captured_at, values: [], sequence, complete: false })
  }
}

///|
pub fn DeviceSnapshot::device_id(self : DeviceSnapshot) -> String {
  self.device_id
}

///|
pub fn DeviceSnapshot::captured_at(self : DeviceSnapshot) -> Int {
  self.captured_at
}

///|
pub fn DeviceSnapshot::sequence(self : DeviceSnapshot) -> Int {
  self.sequence
}

///|
pub fn DeviceSnapshot::value_count(self : DeviceSnapshot) -> Int {
  self.values.length()
}

///|
pub fn DeviceSnapshot::complete(self : DeviceSnapshot) -> Bool {
  self.complete
}

///|
pub fn DeviceSnapshot::add(
  self : DeviceSnapshot,
  value : SnapshotValue,
) -> Result[Unit, ModbusError] {
  if value.timestamp() < self.captured_at {
    return Err(InvalidData)
  }
  for existing in self.values {
    if existing.point_id() == value.point_id() {
      return Err(InvalidData)
    }
  }
  self.values.push(value)
  Ok(())
}

///|
pub fn DeviceSnapshot::finish(
  self : DeviceSnapshot,
  expected : Int,
) -> Result[Unit, ModbusError] {
  if expected < 1 || self.values.length() != expected {
    return Err(Incomplete)
  }
  self.complete = true
  Ok(())
}

///|
pub fn DeviceSnapshot::get(
  self : DeviceSnapshot,
  point_id : String,
) -> SnapshotValue? {
  for value in self.values {
    if value.point_id() == point_id {
      return Some(value)
    }
  }
  None
}

///|
pub fn DeviceSnapshot::good_count(self : DeviceSnapshot) -> Int {
  let mut count = 0
  for value in self.values {
    if value.is_good() {
      count += 1
    }
  }
  count
}

///|
pub fn DeviceSnapshot::quality(self : DeviceSnapshot) -> ReadingQuality {
  if self.values.length() == 0 {
    Stale
  } else if self.good_count() == self.values.length() {
    Good
  } else if self.good_count() == 0 {
    Disconnected
  } else {
    Substituted
  }
}

///|
pub fn DeviceSnapshot::diff(
  self : DeviceSnapshot,
  previous : DeviceSnapshot,
) -> Array[String] {
  let result : Array[String] = []
  for value in self.values {
    match previous.get(value.point_id()) {
      Some(old) =>
        if old.value() != value.value() || old.quality() != value.quality() {
          result.push(value.point_id())
        }
      None => result.push(value.point_id())
    }
  }
  result
}

///|
/// Registry for services and latest snapshots.
pub(all) struct DeviceServiceRegistry {
  services : Array[DeviceService]
  snapshots : Array[DeviceSnapshot]
  max_services : Int
  max_snapshots : Int
}

///|
pub fn DeviceServiceRegistry::new(
  max_services? : Int = 1024,
  max_snapshots? : Int = 4096,
) -> Result[DeviceServiceRegistry, ModbusError] {
  if max_services < 1 || max_snapshots < 1 {
    Err(InvalidData)
  } else {
    Ok({ services: [], snapshots: [], max_services, max_snapshots })
  }
}

///|
pub fn DeviceServiceRegistry::service_count(
  self : DeviceServiceRegistry,
) -> Int {
  self.services.length()
}

///|
pub fn DeviceServiceRegistry::snapshot_count(
  self : DeviceServiceRegistry,
) -> Int {
  self.snapshots.length()
}

///|
pub fn DeviceServiceRegistry::register(
  self : DeviceServiceRegistry,
  service : DeviceService,
) -> Result[Unit, ModbusError] {
  if self.services.length() >= self.max_services {
    return Err(CapacityExceeded)
  }
  for existing in self.services {
    if existing.id() == service.id() {
      return Err(InvalidData)
    }
  }
  self.services.push(service)
  Ok(())
}

///|
pub fn DeviceServiceRegistry::service(
  self : DeviceServiceRegistry,
  id : String,
) -> DeviceService? {
  for service in self.services {
    if service.id() == id {
      return Some(service)
    }
  }
  None
}

///|
pub fn DeviceServiceRegistry::for_device(
  self : DeviceServiceRegistry,
  device_id : String,
) -> Array[DeviceService] {
  let result : Array[DeviceService] = []
  for service in self.services {
    if service.device_id() == device_id {
      result.push(service)
    }
  }
  result
}

///|
pub fn DeviceServiceRegistry::put_snapshot(
  self : DeviceServiceRegistry,
  snapshot : DeviceSnapshot,
) -> Result[Unit, ModbusError] {
  if self.snapshots.length() >= self.max_snapshots {
    ignore(self.snapshots.remove(0))
  }
  for i in 0..<self.snapshots.length() {
    if self.snapshots[i].device_id() == snapshot.device_id() {
      self.snapshots[i] = snapshot
      return Ok(())
    }
  }
  self.snapshots.push(snapshot)
  Ok(())
}

///|
pub fn DeviceServiceRegistry::snapshot(
  self : DeviceServiceRegistry,
  device_id : String,
) -> DeviceSnapshot? {
  for snapshot in self.snapshots {
    if snapshot.device_id() == device_id {
      return Some(snapshot)
    }
  }
  None
}

///|
pub fn DeviceServiceRegistry::running(
  self : DeviceServiceRegistry,
) -> Array[String] {
  let result : Array[String] = []
  for service in self.services {
    if service.state() == ServiceRunning {
      result.push(service.id())
    }
  }
  result
}

///|
pub fn DeviceServiceRegistry::failed(
  self : DeviceServiceRegistry,
) -> Array[String] {
  let result : Array[String] = []
  for service in self.services {
    if service.state() == ServiceFailed {
      result.push(service.id())
    }
  }
  result
}

///|
/// Return a stable line-oriented snapshot for diagnostics and support bundles.
pub fn DeviceServiceRegistry::export_summary(
  self : DeviceServiceRegistry,
) -> Array[String] {
  let lines : Array[String] = []
  for service in self.services {
    lines.push(
      "service=" +
      service.id() +
      " device=" +
      service.device_id() +
      " kind=" +
      device_service_kind_name(service.kind()) +
      " state=" +
      device_service_state_name(service.state()),
    )
  }
  for snapshot in self.snapshots {
    lines.push(
      "snapshot=" +
      snapshot.device_id() +
      " values=" +
      snapshot.value_count().to_string() +
      " complete=" +
      snapshot.complete().to_string() +
      " quality=" +
      reading_quality_name(snapshot.quality()),
    )
  }
  lines
}
