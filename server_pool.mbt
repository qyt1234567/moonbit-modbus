///|
/// Configuration for an in-process Modbus server.
pub(all) struct ServerConfig {
  mode : Mode
  max_devices : Int
  max_frame : Int
  allow_broadcast : Bool
  max_pending_bytes : Int
}

///|
pub fn default_server_config(mode : Mode) -> ServerConfig {
  {
    mode,
    max_devices: 247,
    max_frame: limits_for(mode).max_adu,
    allow_broadcast: true,
    max_pending_bytes: 4096,
  }
}

///|
pub fn validate_server_config(
  config : ServerConfig,
) -> Result[Unit, ModbusError] {
  if config.max_devices < 1 ||
    config.max_devices > 247 ||
    config.max_frame < minimum_frame_length(config.mode) ||
    config.max_pending_bytes < config.max_frame {
    Err(InvalidData)
  } else {
    Ok(())
  }
}

///|
/// A multi-unit server that owns device instances and performs transport framing.
pub struct Server {
  config : ServerConfig
  devices : Array[Device]
  parser : IncrementalParser
  metrics : ProtocolMetrics
  audit : AuditLog
}

///|
pub fn Server::new(config : ServerConfig) -> Result[Server, ModbusError] {
  match validate_server_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let metrics = match ProtocolMetrics::new() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let audit = match AuditLog::new() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    config,
    devices: [],
    parser: IncrementalParser::new(
      config.mode,
      max_frame=config.max_frame,
      role=Request,
    ),
    metrics,
    audit,
  })
}

///|
pub fn Server::config(self : Server) -> ServerConfig {
  self.config
}

///|
pub fn Server::mode(self : Server) -> Mode {
  self.config.mode
}

///|
pub fn Server::add_device(
  self : Server,
  device : Device,
) -> Result[Unit, ModbusError] {
  if self.devices.length() >= self.config.max_devices {
    return Err(CapacityExceeded)
  }
  if self.find_device(device.unit_id()) is Some(_) {
    return Err(InvalidUnitId)
  }
  self.devices.push(device)
  Ok(())
}

///|
pub fn Server::remove_device(
  self : Server,
  unit_id : Byte,
) -> Result[Unit, ModbusError] {
  let index = match self.find_device_index(unit_id) {
    Some(value) => value
    None => return Err(InvalidUnitId)
  }
  let retained : Array[Device] = []
  for current in 0..<self.devices.length() {
    if current != index {
      retained.push(self.devices[current])
    }
  }
  self.devices.clear()
  for device in retained {
    self.devices.push(device)
  }
  Ok(())
}

///|
pub fn Server::device_count(self : Server) -> Int {
  self.devices.length()
}

///|
pub fn Server::device(self : Server, unit_id : Byte) -> Device? {
  self.find_device(unit_id)
}

///|
/// Handle a decoded request and return a decoded reply.
pub fn Server::handle(
  self : Server,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let device = match self.find_device(request.unit_id) {
    Some(value) => value
    None => {
      if request.unit_id == 0 && self.config.allow_broadcast {
        if self.devices.length() == 0 {
          return Err(NoResponse)
        }
        return self.handle_broadcast(request)
      }
      return Err(UnitMismatch)
    }
  }
  match device.handle(request) {
    Ok(response) => {
      let _ = self.metrics.record_response(
        encoded_length(self.config.mode, response),
        1,
        response.is_exception(),
      )
      self.audit.record("request", self.config.mode, 0, request, "handled")
      self.audit.record(
        "response",
        self.config.mode,
        0,
        response,
        response_quality(request, response),
      )
      Ok(response)
    }
    Err(error) => {
      self.metrics.record_error()
      self.audit.record(
        "request",
        self.config.mode,
        0,
        request,
        error_name(error),
      )
      Err(error)
    }
  }
}

///|
/// Decode an ADU, dispatch it, and encode the reply.
pub fn Server::handle_adu(
  self : Server,
  bytes : Array[Byte],
) -> Result[Array[Byte], ModbusError] {
  let (transaction_id, request) = match
    decode_transaction(self.config.mode, bytes) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let response = match self.handle(request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  encode_checked_response(self.config.mode, transaction_id, response)
}

///|
fn encode_checked_response(
  mode : Mode,
  transaction_id : UInt16,
  response : Frame,
) -> Result[Array[Byte], ModbusError] {
  match mode {
    Rtu => Ok(encode_rtu(response))
    Ascii => Ok(encode_ascii(response))
    Tcp => Ok(encode_tcp(transaction_id, response))
  }
}

///|
fn Server::handle_broadcast(
  self : Server,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let mut last_error : ModbusError? = None
  for device in self.devices {
    match device.serve(request) {
      Ok(_) => ()
      Err(error) => last_error = Some(error)
    }
  }
  match last_error {
    Some(error) => Err(error)
    None => Err(NoResponse)
  }
}

///|
fn Server::find_device_index(self : Server, unit_id : Byte) -> Int? {
  for index in 0..<self.devices.length() {
    if self.devices[index].unit_id() == unit_id {
      return Some(index)
    }
  }
  None
}

///|
fn Server::find_device(self : Server, unit_id : Byte) -> Device? {
  match self.find_device_index(unit_id) {
    Some(index) => Some(self.devices[index])
    None => None
  }
}

///|
pub fn Server::parser(self : Server) -> IncrementalParser {
  self.parser
}

///|
pub fn Server::metrics(self : Server) -> ProtocolMetrics {
  self.metrics
}

///|
pub fn Server::audit(self : Server) -> AuditLog {
  self.audit
}

///|
/// Run a request against every configured unit and return normal replies.
pub fn Server::broadcast(self : Server, request : Frame) -> Array[Frame] {
  let replies : Array[Frame] = []
  for device in self.devices {
    match device.serve(request) {
      Ok(Reply(response)) => replies.push(response)
      _ => ()
    }
  }
  replies
}
