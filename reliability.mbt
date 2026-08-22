///|
/// Classification used by reliability counters and incident reports.
pub(all) enum ReliabilityFailure {
  TimeoutFailure
  ChecksumFailure
  ProtocolFailure
  TransportFailure
  DeviceException
  ValidationFailure
} derive(Debug, Eq)

///|
/// State of a circuit guard protecting a device or route.
pub(all) enum CircuitGuardState {
  ClosedCircuit
  OpenCircuit
  HalfOpenCircuit
} derive(Debug, Eq)

///|
/// One outcome recorded by a transport or polling worker.
pub(all) struct ReliabilitySample {
  timestamp : Int
  latency : Int
  success : Bool
  failure : ReliabilityFailure?
  operation : String
}

///|
pub fn ReliabilitySample::new(
  timestamp : Int,
  latency : Int,
  success : Bool,
  operation : String,
  failure? : ReliabilityFailure = TimeoutFailure,
) -> Result[ReliabilitySample, ModbusError] {
  if timestamp < 0 || latency < 0 || operation == "" {
    return Err(InvalidData)
  }
  let selected_failure = if success { None } else { Some(failure) }
  Ok({ timestamp, latency, success, failure: selected_failure, operation })
}

///|
pub fn ReliabilitySample::timestamp(self : ReliabilitySample) -> Int {
  self.timestamp
}

///|
pub fn ReliabilitySample::latency(self : ReliabilitySample) -> Int {
  self.latency
}

///|
pub fn ReliabilitySample::success(self : ReliabilitySample) -> Bool {
  self.success
}

///|
pub fn ReliabilitySample::failure(
  self : ReliabilitySample,
) -> ReliabilityFailure? {
  self.failure
}

///|
pub fn ReliabilitySample::operation(self : ReliabilitySample) -> String {
  self.operation
}

///|
pub fn reliability_failure_name(failure : ReliabilityFailure) -> String {
  match failure {
    TimeoutFailure => "timeout"
    ChecksumFailure => "checksum"
    ProtocolFailure => "protocol"
    TransportFailure => "transport"
    DeviceException => "device-exception"
    ValidationFailure => "validation"
  }
}

///|
/// A bounded sliding window of request outcomes.
pub(all) struct ReliabilityWindow {
  width : Int
  max_samples : Int
  samples : Array[ReliabilitySample]
  mut evicted : Int
}

///|
pub fn ReliabilityWindow::new(
  width : Int,
  max_samples? : Int = 4096,
) -> Result[ReliabilityWindow, ModbusError] {
  if width < 1 || max_samples < 1 {
    Err(InvalidData)
  } else {
    Ok({ width, max_samples, samples: [], evicted: 0 })
  }
}

///|
pub fn ReliabilityWindow::width(self : ReliabilityWindow) -> Int {
  self.width
}

///|
pub fn ReliabilityWindow::length(self : ReliabilityWindow) -> Int {
  self.samples.length()
}

///|
pub fn ReliabilityWindow::evicted(self : ReliabilityWindow) -> Int {
  self.evicted
}

///|
pub fn ReliabilityWindow::append(
  self : ReliabilityWindow,
  sample : ReliabilitySample,
) -> Result[Unit, ModbusError] {
  if self.samples.length() > 0 &&
    sample.timestamp() < self.samples[self.samples.length() - 1].timestamp() {
    return Err(InvalidData)
  }
  self.samples.push(sample)
  ignore(self.prune(sample.timestamp()))
  if self.samples.length() > self.max_samples {
    ignore(self.samples.remove(0))
    self.evicted += 1
  }
  Ok(())
}

///|
pub fn ReliabilityWindow::prune(
  self : ReliabilityWindow,
  now : Int,
) -> Result[Int, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let mut removed = 0
  while self.samples.length() > 0 &&
        now - self.samples[0].timestamp() > self.width {
    ignore(self.samples.remove(0))
    removed += 1
  }
  Ok(removed)
}

///|
pub fn ReliabilityWindow::successes(self : ReliabilityWindow) -> Int {
  let mut count = 0
  for sample in self.samples {
    if sample.success() {
      count += 1
    }
  }
  count
}

///|
pub fn ReliabilityWindow::failures(self : ReliabilityWindow) -> Int {
  self.samples.length() - self.successes()
}

///|
pub fn ReliabilityWindow::success_rate(self : ReliabilityWindow) -> Int {
  if self.samples.length() == 0 {
    0
  } else {
    self.successes() * 100 / self.samples.length()
  }
}

///|
pub fn ReliabilityWindow::average_latency(self : ReliabilityWindow) -> Int {
  if self.samples.length() == 0 {
    return 0
  }
  let mut sum = 0
  for sample in self.samples {
    sum += sample.latency()
  }
  sum / self.samples.length()
}

///|
pub fn ReliabilityWindow::failure_count(
  self : ReliabilityWindow,
  failure : ReliabilityFailure,
) -> Int {
  let mut count = 0
  for sample in self.samples {
    match sample.failure() {
      Some(value) => if value == failure { count += 1 }
      None => ()
    }
  }
  count
}

///|
pub fn ReliabilityWindow::latest(
  self : ReliabilityWindow,
) -> ReliabilitySample? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[self.samples.length() - 1])
  }
}

///|
pub fn ReliabilityWindow::clear(self : ReliabilityWindow) -> Unit {
  self.samples.clear()
}

///|
/// A circuit breaker with failure threshold and recovery probes.
pub(all) struct CircuitGuard {
  name : String
  failure_threshold : Int
  recovery_after : Int
  probe_limit : Int
  mut state : CircuitGuardState
  mut consecutive_failures : Int
  mut opened_at : Int?
  mut probes : Int
}

///|
pub fn CircuitGuard::new(
  name : String,
  failure_threshold : Int,
  recovery_after : Int,
  probe_limit? : Int = 1,
) -> Result[CircuitGuard, ModbusError] {
  if name == "" ||
    failure_threshold < 1 ||
    recovery_after < 1 ||
    probe_limit < 1 {
    return Err(InvalidData)
  }
  Ok({
    name,
    failure_threshold,
    recovery_after,
    probe_limit,
    state: ClosedCircuit,
    consecutive_failures: 0,
    opened_at: None,
    probes: 0,
  })
}

///|
pub fn CircuitGuard::name(self : CircuitGuard) -> String {
  self.name
}

///|
pub fn CircuitGuard::state(self : CircuitGuard) -> CircuitGuardState {
  self.state
}

///|
pub fn CircuitGuard::failure_threshold(self : CircuitGuard) -> Int {
  self.failure_threshold
}

///|
pub fn CircuitGuard::recovery_after(self : CircuitGuard) -> Int {
  self.recovery_after
}

///|
pub fn CircuitGuard::consecutive_failures(self : CircuitGuard) -> Int {
  self.consecutive_failures
}

///|
pub fn CircuitGuard::opened_at(self : CircuitGuard) -> Int? {
  self.opened_at
}

///|
pub fn CircuitGuard::allow(
  self : CircuitGuard,
  now : Int,
) -> Result[Bool, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  match self.state {
    ClosedCircuit => Ok(true)
    HalfOpenCircuit =>
      if self.probes < self.probe_limit {
        self.probes += 1
        Ok(true)
      } else {
        Ok(false)
      }
    OpenCircuit =>
      match self.opened_at {
        Some(opened) =>
          if now - opened >= self.recovery_after {
            self.state = HalfOpenCircuit
            self.probes = 1
            Ok(true)
          } else {
            Ok(false)
          }
        None => Err(InvalidData)
      }
  }
}

///|
pub fn CircuitGuard::record_success(self : CircuitGuard) -> Unit {
  self.consecutive_failures = 0
  self.probes = 0
  self.opened_at = None
  self.state = ClosedCircuit
}

///|
pub fn CircuitGuard::record_failure(
  self : CircuitGuard,
  now : Int,
) -> Result[Unit, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  self.consecutive_failures += 1
  self.probes = 0
  if self.consecutive_failures >= self.failure_threshold {
    self.state = OpenCircuit
    self.opened_at = Some(now)
  }
  Ok(())
}

///|
pub fn CircuitGuard::force_open(
  self : CircuitGuard,
  now : Int,
) -> Result[Unit, ModbusError] {
  if now < 0 {
    Err(InvalidData)
  } else {
    self.state = OpenCircuit
    self.opened_at = Some(now)
    Ok(())
  }
}

///|
pub fn CircuitGuard::force_close(self : CircuitGuard) -> Unit {
  self.record_success()
}

///|
/// Current availability and latency indicators for a device.
pub(all) struct DeviceReliability {
  device_id : String
  window : ReliabilityWindow
  circuit : CircuitGuard
  mut last_seen : Int?
  mut total_requests : Int
  mut total_successes : Int
}

///|
pub fn DeviceReliability::new(
  device_id : String,
  window_width : Int,
  failure_threshold : Int,
  recovery_after : Int,
) -> Result[DeviceReliability, ModbusError] {
  if device_id == "" {
    return Err(InvalidData)
  }
  let window = match ReliabilityWindow::new(window_width) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let circuit = match
    CircuitGuard::new(device_id, failure_threshold, recovery_after) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    device_id,
    window,
    circuit,
    last_seen: None,
    total_requests: 0,
    total_successes: 0,
  })
}

///|
pub fn DeviceReliability::device_id(self : DeviceReliability) -> String {
  self.device_id
}

///|
pub fn DeviceReliability::last_seen(self : DeviceReliability) -> Int? {
  self.last_seen
}

///|
pub fn DeviceReliability::total_requests(self : DeviceReliability) -> Int {
  self.total_requests
}

///|
pub fn DeviceReliability::total_successes(self : DeviceReliability) -> Int {
  self.total_successes
}

///|
pub fn DeviceReliability::state(self : DeviceReliability) -> CircuitGuardState {
  self.circuit.state()
}

///|
pub fn DeviceReliability::success_rate(self : DeviceReliability) -> Int {
  self.window.success_rate()
}

///|
pub fn DeviceReliability::average_latency(self : DeviceReliability) -> Int {
  self.window.average_latency()
}

///|
pub fn DeviceReliability::allow_request(
  self : DeviceReliability,
  now : Int,
) -> Result[Bool, ModbusError] {
  self.circuit.allow(now)
}

///|
/// Record one outcome and update breaker state atomically from the caller's view.
pub fn DeviceReliability::record(
  self : DeviceReliability,
  sample : ReliabilitySample,
) -> Result[Unit, ModbusError] {
  self.total_requests += 1
  if sample.success() {
    self.total_successes += 1
    self.circuit.record_success()
    self.last_seen = Some(sample.timestamp())
  } else {
    match self.circuit.record_failure(sample.timestamp()) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  self.window.append(sample)
}

///|
/// Return a health score from 0 (offline) to 100 (healthy).
pub fn DeviceReliability::health_score(
  self : DeviceReliability,
  now : Int,
) -> Result[Int, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let base = self.success_rate()
  let latency_penalty = if self.average_latency() > 1000 {
    30
  } else {
    self.average_latency() / 50
  }
  let stale_penalty = match self.last_seen {
    Some(timestamp) =>
      if now - timestamp > self.window.width() {
        40
      } else {
        0
      }
    None => 60
  }
  let state_penalty = match self.circuit.state() {
    ClosedCircuit => 0
    HalfOpenCircuit => 20
    OpenCircuit => 60
  }
  let score = base - latency_penalty - stale_penalty - state_penalty
  Ok(if score < 0 { 0 } else if score > 100 { 100 } else { score })
}

///|
pub fn DeviceReliability::failure_breakdown(
  self : DeviceReliability,
) -> Array[Int] {
  [
    self.window.failure_count(TimeoutFailure),
    self.window.failure_count(ChecksumFailure),
    self.window.failure_count(ProtocolFailure),
    self.window.failure_count(TransportFailure),
    self.window.failure_count(DeviceException),
    self.window.failure_count(ValidationFailure),
  ]
}

///|
/// A fleet-level reliability snapshot for dashboards and alert rules.
pub(all) struct ReliabilityFleetSummary {
  devices : Int
  healthy : Int
  degraded : Int
  open_circuits : Int
  average_success_rate : Int
  average_latency : Int
}

///|
pub fn reliability_fleet_summary(
  devices : Array[DeviceReliability],
) -> ReliabilityFleetSummary {
  let mut healthy = 0
  let mut degraded = 0
  let mut open = 0
  let mut rate = 0
  let mut latency = 0
  for device in devices {
    if device.state() == ClosedCircuit && device.success_rate() >= 95 {
      healthy += 1
    } else {
      degraded += 1
    }
    if device.state() == OpenCircuit {
      open += 1
    }
    rate += device.success_rate()
    latency += device.average_latency()
  }
  let count = devices.length()
  {
    devices: count,
    healthy,
    degraded,
    open_circuits: open,
    average_success_rate: if count == 0 {
      0
    } else {
      rate / count
    },
    average_latency: if count == 0 {
      0
    } else {
      latency / count
    },
  }
}

///|
pub fn ReliabilityFleetSummary::devices(self : ReliabilityFleetSummary) -> Int {
  self.devices
}

///|
pub fn ReliabilityFleetSummary::healthy(self : ReliabilityFleetSummary) -> Int {
  self.healthy
}

///|
pub fn ReliabilityFleetSummary::degraded(self : ReliabilityFleetSummary) -> Int {
  self.degraded
}

///|
pub fn ReliabilityFleetSummary::open_circuits(
  self : ReliabilityFleetSummary,
) -> Int {
  self.open_circuits
}

///|
pub fn ReliabilityFleetSummary::average_success_rate(
  self : ReliabilityFleetSummary,
) -> Int {
  self.average_success_rate
}

///|
pub fn ReliabilityFleetSummary::average_latency(
  self : ReliabilityFleetSummary,
) -> Int {
  self.average_latency
}
