///|
/// Transport mode used for operational metrics.
pub(all) enum MetricsTransport {
  MetricsRtu
  MetricsAscii
  MetricsTcp
  MetricsTls
  MetricsVirtual
} derive(Debug, Eq)

///|
/// Request outcome accumulated by a transport lane.
pub(all) struct TransportMetricWindow {
  transport : MetricsTransport
  window : Int
  mut requests : Int
  mut successes : Int
  mut failures : Int
  mut bytes_sent : Int
  mut bytes_received : Int
  mut latency_total : Int
  mut latency_max : Int
  mut last_timestamp : Int
}

///|
pub fn TransportMetricWindow::new(
  transport : MetricsTransport,
  window : Int,
) -> Result[TransportMetricWindow, ModbusError] {
  if window < 1 {
    Err(InvalidData)
  } else {
    Ok({
      transport,
      window,
      requests: 0,
      successes: 0,
      failures: 0,
      bytes_sent: 0,
      bytes_received: 0,
      latency_total: 0,
      latency_max: 0,
      last_timestamp: 0,
    })
  }
}

///|
pub fn TransportMetricWindow::transport(
  self : TransportMetricWindow,
) -> MetricsTransport {
  self.transport
}

///|
pub fn TransportMetricWindow::window(self : TransportMetricWindow) -> Int {
  self.window
}

///|
pub fn TransportMetricWindow::requests(self : TransportMetricWindow) -> Int {
  self.requests
}

///|
pub fn TransportMetricWindow::successes(self : TransportMetricWindow) -> Int {
  self.successes
}

///|
pub fn TransportMetricWindow::failures(self : TransportMetricWindow) -> Int {
  self.failures
}

///|
pub fn TransportMetricWindow::bytes_sent(self : TransportMetricWindow) -> Int {
  self.bytes_sent
}

///|
pub fn TransportMetricWindow::bytes_received(
  self : TransportMetricWindow,
) -> Int {
  self.bytes_received
}

///|
pub fn TransportMetricWindow::average_latency(
  self : TransportMetricWindow,
) -> Int {
  if self.requests == 0 {
    0
  } else {
    self.latency_total / self.requests
  }
}

///|
pub fn TransportMetricWindow::maximum_latency(
  self : TransportMetricWindow,
) -> Int {
  self.latency_max
}

///|
pub fn TransportMetricWindow::success_rate(self : TransportMetricWindow) -> Int {
  if self.requests == 0 {
    0
  } else {
    self.successes * 100 / self.requests
  }
}

///|
pub fn TransportMetricWindow::record(
  self : TransportMetricWindow,
  timestamp : Int,
  success : Bool,
  latency : Int,
  sent : Int,
  received : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < self.last_timestamp || latency < 0 || sent < 0 || received < 0 {
    return Err(InvalidData)
  }
  self.requests += 1
  if success {
    self.successes += 1
  } else {
    self.failures += 1
  }
  self.bytes_sent += sent
  self.bytes_received += received
  self.latency_total += latency
  if latency > self.latency_max {
    self.latency_max = latency
  }
  self.last_timestamp = timestamp
  Ok(())
}

///|
pub fn TransportMetricWindow::reset(self : TransportMetricWindow) -> Unit {
  self.requests = 0
  self.successes = 0
  self.failures = 0
  self.bytes_sent = 0
  self.bytes_received = 0
  self.latency_total = 0
  self.latency_max = 0
}

///|
pub fn metrics_transport_name(transport : MetricsTransport) -> String {
  match transport {
    MetricsRtu => "rtu"
    MetricsAscii => "ascii"
    MetricsTcp => "tcp"
    MetricsTls => "tls"
    MetricsVirtual => "virtual"
  }
}

///|
/// Fleet transport metrics registry.
pub(all) struct TransportMetricsRegistry {
  windows : Array[TransportMetricWindow]
  max_windows : Int
}

///|
pub fn TransportMetricsRegistry::new(
  max_windows? : Int = 32,
  window? : Int = 60000,
) -> Result[TransportMetricsRegistry, ModbusError] {
  if max_windows < 1 || window < 1 {
    return Err(InvalidData)
  }
  let registry = { windows: [], max_windows }
  for
    transport in [
      MetricsRtu,
      MetricsAscii,
      MetricsTcp,
      MetricsTls,
      MetricsVirtual,
    ] {
    let metric = match TransportMetricWindow::new(transport, window) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    registry.windows.push(metric)
  }
  Ok(registry)
}

///|
pub fn TransportMetricsRegistry::count(self : TransportMetricsRegistry) -> Int {
  self.windows.length()
}

///|
pub fn TransportMetricsRegistry::window(
  self : TransportMetricsRegistry,
  transport : MetricsTransport,
) -> TransportMetricWindow? {
  for window in self.windows {
    if window.transport() == transport {
      return Some(window)
    }
  }
  None
}

///|
pub fn TransportMetricsRegistry::record(
  self : TransportMetricsRegistry,
  transport : MetricsTransport,
  timestamp : Int,
  success : Bool,
  latency : Int,
  sent : Int,
  received : Int,
) -> Result[Unit, ModbusError] {
  match self.window(transport) {
    Some(window) => window.record(timestamp, success, latency, sent, received)
    None => Err(InvalidData)
  }
}

///|
pub fn TransportMetricsRegistry::total_requests(
  self : TransportMetricsRegistry,
) -> Int {
  let mut total = 0
  for window in self.windows {
    total += window.requests()
  }
  total
}

///|
pub fn TransportMetricsRegistry::total_failures(
  self : TransportMetricsRegistry,
) -> Int {
  let mut total = 0
  for window in self.windows {
    total += window.failures()
  }
  total
}

///|
pub fn TransportMetricsRegistry::export_lines(
  self : TransportMetricsRegistry,
) -> Array[String] {
  let lines : Array[String] = []
  for window in self.windows {
    lines.push(
      "transport=" +
      metrics_transport_name(window.transport()) +
      " requests=" +
      window.requests().to_string() +
      " success_rate=" +
      window.success_rate().to_string() +
      " avg_latency=" +
      window.average_latency().to_string() +
      " max_latency=" +
      window.maximum_latency().to_string() +
      " tx_bytes=" +
      window.bytes_sent().to_string() +
      " rx_bytes=" +
      window.bytes_received().to_string(),
    )
  }
  lines
}
