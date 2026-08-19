///|
/// Serial-line parameters independent of any concrete serial-port library.
pub(all) struct SerialConfig {
  path : String
  baud : Int
  data_bits : Int
  stop_bits : Int
  parity : Byte
  mode : Mode
}

///|
pub fn SerialConfig::new(
  path : String,
  baud : Int,
  mode : Mode,
  data_bits? : Int = 8,
  stop_bits? : Int = 1,
  parity? : Byte = 0,
) -> Result[SerialConfig, ModbusError] {
  if path.length() == 0 ||
    baud < 300 ||
    data_bits < 5 ||
    data_bits > 8 ||
    stop_bits < 1 ||
    stop_bits > 2 ||
    parity > 2 ||
    !transport_is_serial(mode) {
    Err(InvalidData)
  } else {
    Ok({ path, baud, data_bits, stop_bits, parity, mode })
  }
}

///|
pub fn SerialConfig::parity_name(self : SerialConfig) -> String {
  match self.parity {
    0 => "none"
    1 => "odd"
    _ => "even"
  }
}

///|
/// TCP endpoint settings.
pub(all) struct TcpConfig {
  host : String
  port : Int
  connect_timeout : Int
  keep_alive : Bool
}

///|
pub fn TcpConfig::new(
  host : String,
  port : Int,
  connect_timeout? : Int = 5000,
  keep_alive? : Bool = true,
) -> Result[TcpConfig, ModbusError] {
  if host.length() == 0 || port < 1 || port > 65535 || connect_timeout < 1 {
    Err(InvalidData)
  } else {
    Ok({ host, port, connect_timeout, keep_alive })
  }
}

///|
pub fn TcpConfig::address(self : TcpConfig) -> String {
  self.host + ":" + self.port.to_string()
}

///|
/// A transport endpoint configuration.
pub(all) enum EndpointConfig {
  Serial(SerialConfig)
  Tcp(TcpConfig)
}

///|
pub fn EndpointConfig::mode(config : EndpointConfig) -> Mode {
  match config {
    Serial(value) => value.mode
    Tcp(_) => Tcp
  }
}

///|
pub fn EndpointConfig::name(config : EndpointConfig) -> String {
  match config {
    Serial(value) => value.path
    Tcp(value) => value.address()
  }
}

///|
pub fn validate_endpoint(config : EndpointConfig) -> Result[Unit, ModbusError] {
  match config {
    Serial(value) =>
      if value.path.length() > 0 {
        Ok(())
      } else {
        Err(InvalidData)
      }
    Tcp(value) =>
      if value.port > 0 && value.port <= 65535 {
        Ok(())
      } else {
        Err(InvalidData)
      }
  }
}

///|
/// Lifecycle state of a transport endpoint.
pub(all) enum EndpointState {
  Closed
  Connecting
  Ready
  Backoff
  Faulted
} derive(Debug, Eq)

///|
/// Runtime state tracked independently from operating-system handles.
pub(all) struct EndpointRuntime {
  config : EndpointConfig
  mut state : EndpointState
  mut opened_at : Int
  mut last_error : ModbusError?
  mut reconnects : Int
  mut frames_in : Int
  mut frames_out : Int
}

///|
pub fn EndpointRuntime::new(
  config : EndpointConfig,
) -> Result[EndpointRuntime, ModbusError] {
  match validate_endpoint(config) {
    Err(error) => Err(error)
    Ok(_) =>
      Ok({
        config,
        state: Closed,
        opened_at: 0,
        last_error: None,
        reconnects: 0,
        frames_in: 0,
        frames_out: 0,
      })
  }
}

///|
pub fn EndpointRuntime::open(
  self : EndpointRuntime,
  now : Int,
) -> Result[Unit, ModbusError] {
  if now < 0 || self.state == Ready || self.state == Connecting {
    return Err(Busy)
  }
  self.state = Connecting
  self.opened_at = now
  self.state = Ready
  self.reconnects += 1
  self.last_error = None
  Ok(())
}

///|
pub fn EndpointRuntime::close(self : EndpointRuntime) -> Unit {
  self.state = Closed
}

///|
pub fn EndpointRuntime::fail(
  self : EndpointRuntime,
  error : ModbusError,
) -> Unit {
  self.state = Faulted
  self.last_error = Some(error)
}

///|
pub fn EndpointRuntime::backoff(self : EndpointRuntime) -> Unit {
  self.state = Backoff
}

///|
pub fn EndpointRuntime::state(self : EndpointRuntime) -> EndpointState {
  self.state
}

///|
pub fn EndpointRuntime::config(self : EndpointRuntime) -> EndpointConfig {
  self.config
}

///|
pub fn EndpointRuntime::record_in(
  self : EndpointRuntime,
) -> Result[Unit, ModbusError] {
  if self.state != Ready {
    Err(NoResponse)
  } else {
    self.frames_in += 1
    Ok(())
  }
}

///|
pub fn EndpointRuntime::record_out(
  self : EndpointRuntime,
) -> Result[Unit, ModbusError] {
  if self.state != Ready {
    Err(NoResponse)
  } else {
    self.frames_out += 1
    Ok(())
  }
}

///|
pub fn EndpointRuntime::uptime(self : EndpointRuntime, now : Int) -> Int {
  if self.state == Ready && now >= self.opened_at {
    now - self.opened_at
  } else {
    0
  }
}

///|
pub fn EndpointRuntime::reconnects(self : EndpointRuntime) -> Int {
  self.reconnects
}

///|
pub fn EndpointRuntime::frames_in(self : EndpointRuntime) -> Int {
  self.frames_in
}

///|
pub fn EndpointRuntime::frames_out(self : EndpointRuntime) -> Int {
  self.frames_out
}

///|
pub fn EndpointRuntime::last_error(self : EndpointRuntime) -> ModbusError? {
  self.last_error
}
