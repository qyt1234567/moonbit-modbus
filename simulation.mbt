///|
/// Deterministic fault modes for protocol integration tests.
pub(all) enum FaultMode {
  NoFault
  DropResponse
  CorruptCrc
  CorruptLrc
  WrongTransaction
  BusyDevice
  InvalidFunction
} derive(Debug, Eq)

///|
pub fn fault_mode_name(mode : FaultMode) -> String {
  match mode {
    NoFault => "none"
    DropResponse => "drop-response"
    CorruptCrc => "corrupt-crc"
    CorruptLrc => "corrupt-lrc"
    WrongTransaction => "wrong-transaction"
    BusyDevice => "busy-device"
    InvalidFunction => "invalid-function"
  }
}

///|
/// Result of one deterministic simulation step.
pub(all) enum SimulationResult {
  Delivered(Frame)
  Dropped
  Rejected(ModbusError)
}

///|
/// A portable protocol simulation with no operating-system I/O.
pub struct Simulation {
  device : Device
  mode : Mode
  mut fault : FaultMode
  mut clock : Int
  metrics : ProtocolMetrics
  audit : AuditLog
}

///|
pub fn Simulation::new(
  device : Device,
  mode : Mode,
) -> Result[Simulation, ModbusError] {
  let metrics = match ProtocolMetrics::new() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let audit = match AuditLog::new() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ device, mode, fault: NoFault, clock: 0, metrics, audit })
}

///|
pub fn Simulation::device(self : Simulation) -> Device {
  self.device
}

///|
pub fn Simulation::mode(self : Simulation) -> Mode {
  self.mode
}

///|
pub fn Simulation::clock(self : Simulation) -> Int {
  self.clock
}

///|
pub fn Simulation::set_fault(self : Simulation, fault : FaultMode) -> Unit {
  self.fault = fault
  if fault == BusyDevice {
    self.device.set_busy(true)
  } else {
    self.device.set_busy(false)
  }
}

///|
pub fn Simulation::fault(self : Simulation) -> FaultMode {
  self.fault
}

///|
pub fn Simulation::advance(
  self : Simulation,
  ticks : Int,
) -> Result[Unit, ModbusError] {
  if ticks < 0 {
    Err(InvalidData)
  } else {
    self.clock += ticks
    Ok(())
  }
}

///|
/// Send one request through the selected fault model.
pub fn Simulation::request(
  self : Simulation,
  transaction_id : UInt16,
  request : Frame,
) -> SimulationResult {
  let request_bytes = encode_mode(self.mode, request)
  let _ = self.metrics.record_request(request_bytes.length())
  self.audit.record("request", self.mode, transaction_id, request, "sent")
  match self.fault {
    DropResponse => {
      self.audit.record("device", self.mode, transaction_id, request, "dropped")
      SimulationResult::Dropped
    }
    InvalidFunction => {
      let response = exception_response(request.unit_id, 0x7F, 1)
      self.audit.record(
        "response",
        self.mode,
        transaction_id,
        response,
        "invalid-function",
      )
      SimulationResult::Delivered(response)
    }
    _ =>
      match self.device.handle(request) {
        Err(error) => {
          let _ = self.metrics.record_error()
          self.audit.record(
            "device",
            self.mode,
            transaction_id,
            request,
            error_name(error),
          )
          SimulationResult::Rejected(error)
        }
        Ok(response) => {
          let outcome = if self.fault == WrongTransaction && self.mode == Tcp {
            "wrong-transaction"
          } else {
            "delivered"
          }
          let bytes = encode_mode(self.mode, response)
          let exception = response.is_exception()
          let _ = self.metrics.record_response(bytes.length(), 1, exception)
          self.audit.record(
            "response",
            self.mode,
            transaction_id,
            response,
            outcome,
          )
          SimulationResult::Delivered(response)
        }
      }
  }
}

///|
pub fn Simulation::metrics(self : Simulation) -> ProtocolMetrics {
  self.metrics
}

///|
pub fn Simulation::audit(self : Simulation) -> AuditLog {
  self.audit
}

///|
pub fn Simulation::reset(self : Simulation) -> Unit {
  self.clock = 0
  self.fault = NoFault
  self.device.set_busy(false)
  self.audit.clear()
}

///|
/// A deterministic multi-request scenario.
pub(all) struct Scenario {
  name : String
  requests : Array[Frame]
  mode : Mode
}

///|
pub fn Scenario::new(name : String, mode : Mode) -> Scenario {
  { name, requests: [], mode }
}

///|
pub fn Scenario::add(
  self : Scenario,
  request : Frame,
) -> Result[Unit, ModbusError] {
  if self.requests.length() >= 1024 {
    Err(CapacityExceeded)
  } else {
    self.requests.push(request)
    Ok(())
  }
}

///|
pub fn Scenario::length(self : Scenario) -> Int {
  self.requests.length()
}

///|
pub fn Scenario::name(self : Scenario) -> String {
  self.name
}

///|
pub fn Scenario::mode(self : Scenario) -> Mode {
  self.mode
}

///|
pub fn Scenario::run(
  self : Scenario,
  simulation : Simulation,
) -> Array[SimulationResult] {
  let out : Array[SimulationResult] = []
  for index, request in self.requests {
    out.push(simulation.request(index.to_uint16(), request))
    let _ = simulation.advance(1)
  }
  out
}

///|
/// Count successful deliveries in a scenario result.
pub fn simulation_successes(results : Array[SimulationResult]) -> Int {
  let mut count = 0
  for result in results {
    if result is Delivered(_) {
      count += 1
    }
  }
  count
}

///|
pub fn simulation_failures(results : Array[SimulationResult]) -> Int {
  results.length() - simulation_successes(results)
}
