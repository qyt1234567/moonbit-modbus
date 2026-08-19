///|
/// A small integer counter used for protocol telemetry.
pub(all) struct Counter {
  name : String
  mut value : Int
}

///|
pub fn Counter::new(name : String) -> Counter {
  { name, value: 0 }
}

///|
pub fn Counter::name(self : Counter) -> String {
  self.name
}

///|
pub fn Counter::value(self : Counter) -> Int {
  self.value
}

///|
pub fn Counter::inc(self : Counter) -> Unit {
  self.value += 1
}

///|
pub fn Counter::add(self : Counter, amount : Int) -> Result[Unit, ModbusError] {
  if amount < 0 {
    Err(InvalidData)
  } else {
    self.value += amount
    Ok(())
  }
}

///|
pub fn Counter::reset(self : Counter) -> Unit {
  self.value = 0
}

///|
/// Fixed latency buckets, expressed in logical ticks.
pub(all) struct LatencyHistogram {
  bounds : Array[Int]
  counts : Array[Int]
  mut total : Int
  mut sum : Int
}

///|
pub fn LatencyHistogram::new(
  bounds : Array[Int],
) -> Result[LatencyHistogram, ModbusError] {
  if bounds.length() == 0 {
    return Err(InvalidData)
  }
  for index in 1..<bounds.length() {
    if bounds[index] <= bounds[index - 1] {
      return Err(InvalidData)
    }
  }
  let counts : Array[Int] = []
  for _ in 0..<(bounds.length() + 1) {
    counts.push(0)
  }
  Ok({ bounds, counts, total: 0, sum: 0 })
}

///|
pub fn LatencyHistogram::observe(
  self : LatencyHistogram,
  ticks : Int,
) -> Result[Unit, ModbusError] {
  if ticks < 0 {
    return Err(InvalidData)
  }
  let mut bucket = self.bounds.length()
  for index, bound in self.bounds {
    if ticks <= bound {
      bucket = index
      break
    }
  }
  self.counts[bucket] += 1
  self.total += 1
  self.sum += ticks
  Ok(())
}

///|
pub fn LatencyHistogram::total(self : LatencyHistogram) -> Int {
  self.total
}

///|
pub fn LatencyHistogram::sum(self : LatencyHistogram) -> Int {
  self.sum
}

///|
pub fn LatencyHistogram::mean(self : LatencyHistogram) -> Float {
  if self.total == 0 {
    0.0
  } else {
    Float::from_int(self.sum) / Float::from_int(self.total)
  }
}

///|
pub fn LatencyHistogram::bucket_counts(self : LatencyHistogram) -> Array[Int] {
  let out : Array[Int] = []
  for count in self.counts {
    out.push(count)
  }
  out
}

///|
/// A snapshot-friendly metrics set for a protocol endpoint.
pub(all) struct ProtocolMetrics {
  mut requests : Int
  mut responses : Int
  mut exceptions : Int
  mut errors : Int
  mut bytes_in : Int
  mut bytes_out : Int
  mut active : Int
  latency : LatencyHistogram
}

///|
pub fn ProtocolMetrics::new() -> Result[ProtocolMetrics, ModbusError] {
  match LatencyHistogram::new([1, 5, 10, 25, 50, 100, 250, 1000]) {
    Ok(latency) =>
      Ok({
        requests: 0,
        responses: 0,
        exceptions: 0,
        errors: 0,
        bytes_in: 0,
        bytes_out: 0,
        active: 0,
        latency,
      })
    Err(error) => Err(error)
  }
}

///|
pub fn ProtocolMetrics::record_request(
  self : ProtocolMetrics,
  bytes : Int,
) -> Result[Unit, ModbusError] {
  if bytes < 0 {
    Err(InvalidData)
  } else {
    self.requests += 1
    self.active += 1
    self.bytes_out += bytes
    Ok(())
  }
}

///|
pub fn ProtocolMetrics::record_response(
  self : ProtocolMetrics,
  bytes : Int,
  latency : Int,
  exception : Bool,
) -> Result[Unit, ModbusError] {
  if bytes < 0 || latency < 0 {
    return Err(InvalidData)
  }
  self.responses += 1
  if self.active > 0 {
    self.active -= 1
  }
  self.bytes_in += bytes
  if exception {
    self.exceptions += 1
  }
  self.latency.observe(latency)
}

///|
pub fn ProtocolMetrics::record_error(self : ProtocolMetrics) -> Unit {
  self.errors += 1
  if self.active > 0 {
    self.active -= 1
  }
}

///|
pub fn ProtocolMetrics::requests(self : ProtocolMetrics) -> Int {
  self.requests
}

///|
pub fn ProtocolMetrics::responses(self : ProtocolMetrics) -> Int {
  self.responses
}

///|
pub fn ProtocolMetrics::exceptions(self : ProtocolMetrics) -> Int {
  self.exceptions
}

///|
pub fn ProtocolMetrics::errors(self : ProtocolMetrics) -> Int {
  self.errors
}

///|
pub fn ProtocolMetrics::active(self : ProtocolMetrics) -> Int {
  self.active
}

///|
pub fn ProtocolMetrics::throughput(
  self : ProtocolMetrics,
  ticks : Int,
) -> Float {
  if ticks <= 0 {
    0.0
  } else {
    Float::from_int(self.responses) / Float::from_int(ticks)
  }
}

///|
/// A trace record suitable for debugging a gateway or device exchange.
pub(all) struct AuditEntry {
  sequence : Int
  direction : String
  mode : Mode
  transaction_id : UInt16
  summary : FrameSummary
  outcome : String
}

///|
pub struct AuditLog {
  entries : Array[AuditEntry]
  max_entries : Int
  mut next_sequence : Int
}

///|
pub fn AuditLog::new(
  max_entries? : Int = 1024,
) -> Result[AuditLog, ModbusError] {
  if max_entries < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ entries: [], max_entries, next_sequence: 0 })
  }
}

///|
pub fn AuditLog::record(
  self : AuditLog,
  direction : String,
  mode : Mode,
  transaction_id : UInt16,
  frame : Frame,
  outcome : String,
) -> Unit {
  if self.entries.length() >= self.max_entries {
    let retained : Array[AuditEntry] = []
    for index in 1..<self.entries.length() {
      retained.push(self.entries[index])
    }
    self.entries.clear()
    for entry in retained {
      self.entries.push(entry)
    }
  }
  self.entries.push({
    sequence: self.next_sequence,
    direction,
    mode,
    transaction_id,
    summary: summarize(frame),
    outcome,
  })
  self.next_sequence += 1
}

///|
pub fn AuditLog::length(self : AuditLog) -> Int {
  self.entries.length()
}

///|
pub fn AuditLog::snapshot(self : AuditLog) -> Array[AuditEntry] {
  let out : Array[AuditEntry] = []
  for entry in self.entries {
    out.push(entry)
  }
  out
}

///|
pub fn AuditLog::clear(self : AuditLog) -> Unit {
  self.entries.clear()
}
