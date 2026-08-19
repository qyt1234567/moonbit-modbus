///|
/// A bounded ring of integer telemetry samples for device dashboards.
pub(all) struct TelemetryRing {
  values : Array[Int]
  capacity : Int
  mut cursor : Int
  mut count : Int
}

///|
pub fn TelemetryRing::new(capacity : Int) -> Result[TelemetryRing, ModbusError] {
  if capacity < 1 {
    Err(CapacityExceeded)
  } else {
    let values : Array[Int] = []
    for _ in 0..<capacity {
      values.push(0)
    }
    Ok({ values, capacity, cursor: 0, count: 0 })
  }
}

///|
pub fn TelemetryRing::capacity(self : TelemetryRing) -> Int {
  self.capacity
}

///|
pub fn TelemetryRing::length(self : TelemetryRing) -> Int {
  self.count
}

///|
pub fn TelemetryRing::is_full(self : TelemetryRing) -> Bool {
  self.count == self.capacity
}

///|
/// Add a sample and overwrite the oldest sample when the ring is full.
pub fn TelemetryRing::record(self : TelemetryRing, value : Int) -> Unit {
  self.values[self.cursor] = value
  self.cursor = (self.cursor + 1) % self.capacity
  if self.count < self.capacity {
    self.count += 1
  }
}

///|
fn TelemetryRing::physical_index(self : TelemetryRing, logical : Int) -> Int {
  let first = if self.count == self.capacity { self.cursor } else { 0 }
  (first + logical) % self.capacity
}

///|
/// Read a sample from oldest to newest order.
pub fn TelemetryRing::at(
  self : TelemetryRing,
  logical : Int,
) -> Result[Int, ModbusError] {
  if logical < 0 || logical >= self.count {
    Err(Incomplete)
  } else {
    Ok(self.values[self.physical_index(logical)])
  }
}

///|
pub fn TelemetryRing::latest(self : TelemetryRing) -> Result[Int, ModbusError] {
  if self.count == 0 {
    Err(Incomplete)
  } else {
    self.at(self.count - 1)
  }
}

///|
pub fn TelemetryRing::previous(
  self : TelemetryRing,
) -> Result[Int, ModbusError] {
  if self.count < 2 {
    Err(Incomplete)
  } else {
    self.at(self.count - 2)
  }
}

///|
pub fn TelemetryRing::delta(self : TelemetryRing) -> Result[Int, ModbusError] {
  match (self.latest(), self.previous()) {
    (Ok(latest), Ok(previous)) => Ok(latest - previous)
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }
}

///|
pub fn TelemetryRing::sum(self : TelemetryRing) -> Int {
  let mut result = 0
  for index in 0..<self.count {
    result += self.values[self.physical_index(index)]
  }
  result
}

///|
pub fn TelemetryRing::minimum(self : TelemetryRing) -> Result[Int, ModbusError] {
  if self.count == 0 {
    return Err(Incomplete)
  }
  let mut result = self.values[self.physical_index(0)]
  for index in 1..<self.count {
    let value = self.values[self.physical_index(index)]
    if value < result {
      result = value
    }
  }
  Ok(result)
}

///|
pub fn TelemetryRing::maximum(self : TelemetryRing) -> Result[Int, ModbusError] {
  if self.count == 0 {
    return Err(Incomplete)
  }
  let mut result = self.values[self.physical_index(0)]
  for index in 1..<self.count {
    let value = self.values[self.physical_index(index)]
    if value > result {
      result = value
    }
  }
  Ok(result)
}

///|
pub fn TelemetryRing::average(self : TelemetryRing) -> Float {
  if self.count == 0 {
    0.0
  } else {
    Float::from_int(self.sum()) / Float::from_int(self.count)
  }
}

///|
pub fn TelemetryRing::snapshot(self : TelemetryRing) -> Array[Int] {
  let result : Array[Int] = []
  for index in 0..<self.count {
    result.push(self.values[self.physical_index(index)])
  }
  result
}

///|
pub fn TelemetryRing::clear(self : TelemetryRing) -> Unit {
  self.cursor = 0
  self.count = 0
}

///|
/// A closed interval used for a device alarm threshold.
pub(all) struct Threshold {
  low : Int
  high : Int
}

///|
pub fn Threshold::new(low : Int, high : Int) -> Result[Threshold, ModbusError] {
  if low > high {
    Err(InvalidData)
  } else {
    Ok({ low, high })
  }
}

///|
pub fn Threshold::low(self : Threshold) -> Int {
  self.low
}

///|
pub fn Threshold::high(self : Threshold) -> Int {
  self.high
}

///|
pub(all) enum ThresholdState {
  Below
  Within
  Above
} derive(Debug, Eq)

///|
pub fn Threshold::classify(self : Threshold, value : Int) -> ThresholdState {
  if value < self.low {
    Below
  } else if value > self.high {
    Above
  } else {
    Within
  }
}

///|
/// Stateful threshold monitor that counts state transitions.
pub(all) struct AlarmMonitor {
  threshold : Threshold
  mut state : ThresholdState
  mut transitions : Int
  mut last_value : Int?
}

///|
pub fn AlarmMonitor::new(threshold : Threshold) -> AlarmMonitor {
  { threshold, state: Within, transitions: 0, last_value: None }
}

///|
pub fn AlarmMonitor::threshold(self : AlarmMonitor) -> Threshold {
  self.threshold
}

///|
pub fn AlarmMonitor::state(self : AlarmMonitor) -> ThresholdState {
  self.state
}

///|
pub fn AlarmMonitor::transitions(self : AlarmMonitor) -> Int {
  self.transitions
}

///|
pub fn AlarmMonitor::last_value(self : AlarmMonitor) -> Int? {
  self.last_value
}

///|
pub fn AlarmMonitor::observe(
  self : AlarmMonitor,
  value : Int,
) -> ThresholdState {
  let next = self.threshold.classify(value)
  if self.last_value is Some(_) && next != self.state {
    self.transitions += 1
  }
  self.state = next
  self.last_value = Some(value)
  next
}

///|
pub fn AlarmMonitor::reset(self : AlarmMonitor) -> Unit {
  self.state = Within
  self.transitions = 0
  self.last_value = None
}
