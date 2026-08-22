///|
/// Storage type of a metric emitted by a Modbus service.
pub(all) enum MetricKind {
  CounterMetric
  GaugeMetric
  DurationMetric
  RatioMetric
  EventMetric
} derive(Debug, Eq)

///|
/// A metric sample with a small, allocation-friendly label set.
pub(all) struct ServiceMetric {
  name : String
  kind : MetricKind
  value : Int
  timestamp : Int
  labels : Array[(String, String)]
}

///|
pub fn ServiceMetric::new(
  name : String,
  kind : MetricKind,
  value : Int,
  timestamp : Int,
) -> Result[ServiceMetric, ModbusError] {
  if name == "" || timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ name, kind, value, timestamp, labels: [] })
  }
}

///|
pub fn ServiceMetric::name(self : ServiceMetric) -> String {
  self.name
}

///|
pub fn ServiceMetric::kind(self : ServiceMetric) -> MetricKind {
  self.kind
}

///|
pub fn ServiceMetric::value(self : ServiceMetric) -> Int {
  self.value
}

///|
pub fn ServiceMetric::timestamp(self : ServiceMetric) -> Int {
  self.timestamp
}

///|
pub fn ServiceMetric::label_count(self : ServiceMetric) -> Int {
  self.labels.length()
}

///|
pub fn ServiceMetric::label(self : ServiceMetric, key : String) -> String? {
  for item in self.labels {
    if item.0 == key {
      return Some(item.1)
    }
  }
  None
}

///|
pub fn ServiceMetric::with_label(
  self : ServiceMetric,
  key : String,
  value : String,
) -> Result[Unit, ModbusError] {
  if key == "" {
    return Err(InvalidData)
  }
  for i in 0..<self.labels.length() {
    if self.labels[i].0 == key {
      self.labels[i] = (key, value)
      return Ok(())
    }
  }
  if self.labels.length() >= 12 {
    return Err(CapacityExceeded)
  }
  self.labels.push((key, value))
  Ok(())
}

///|
pub fn metric_kind_name(kind : MetricKind) -> String {
  match kind {
    CounterMetric => "counter"
    GaugeMetric => "gauge"
    DurationMetric => "duration"
    RatioMetric => "ratio"
    EventMetric => "event"
  }
}

///|
/// Bounded history for one named metric.
pub(all) struct MetricSeries {
  name : String
  kind : MetricKind
  capacity : Int
  samples : Array[ServiceMetric]
  mut dropped : Int
}

///|
pub fn MetricSeries::new(
  name : String,
  kind : MetricKind,
  capacity? : Int = 1024,
) -> Result[MetricSeries, ModbusError] {
  if name == "" || capacity < 1 {
    Err(InvalidData)
  } else {
    Ok({ name, kind, capacity, samples: [], dropped: 0 })
  }
}

///|
pub fn MetricSeries::name(self : MetricSeries) -> String {
  self.name
}

///|
pub fn MetricSeries::kind(self : MetricSeries) -> MetricKind {
  self.kind
}

///|
pub fn MetricSeries::length(self : MetricSeries) -> Int {
  self.samples.length()
}

///|
pub fn MetricSeries::dropped(self : MetricSeries) -> Int {
  self.dropped
}

///|
pub fn MetricSeries::append(
  self : MetricSeries,
  metric : ServiceMetric,
) -> Result[Unit, ModbusError] {
  if metric.name() != self.name || metric.kind() != self.kind {
    return Err(UnitMismatch)
  }
  if self.samples.length() > 0 &&
    metric.timestamp() < self.samples[self.samples.length() - 1].timestamp() {
    return Err(InvalidData)
  }
  if self.samples.length() >= self.capacity {
    ignore(self.samples.remove(0))
    self.dropped += 1
  }
  self.samples.push(metric)
  Ok(())
}

///|
pub fn MetricSeries::latest(self : MetricSeries) -> ServiceMetric? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[self.samples.length() - 1])
  }
}

///|
pub fn MetricSeries::sum(self : MetricSeries) -> Int {
  let mut sum = 0
  for metric in self.samples {
    sum += metric.value()
  }
  sum
}

///|
pub fn MetricSeries::minimum(self : MetricSeries) -> Int? {
  if self.samples.length() == 0 {
    return None
  }
  let mut value = self.samples[0].value()
  for metric in self.samples {
    if metric.value() < value {
      value = metric.value()
    }
  }
  Some(value)
}

///|
pub fn MetricSeries::maximum(self : MetricSeries) -> Int? {
  if self.samples.length() == 0 {
    return None
  }
  let mut value = self.samples[0].value()
  for metric in self.samples {
    if metric.value() > value {
      value = metric.value()
    }
  }
  Some(value)
}

///|
pub fn MetricSeries::average(self : MetricSeries) -> Int? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.sum() / self.samples.length())
  }
}

///|
pub fn MetricSeries::between(
  self : MetricSeries,
  start : Int,
  end : Int,
) -> Result[Array[ServiceMetric], ModbusError] {
  if start < 0 || end < start {
    return Err(InvalidData)
  }
  let result : Array[ServiceMetric] = []
  for metric in self.samples {
    if metric.timestamp() >= start && metric.timestamp() <= end {
      result.push(metric)
    }
  }
  Ok(result)
}

///|
/// A registry used by transports, schedulers, and HTTP adapters.
pub(all) struct MetricRegistry {
  series : Array[MetricSeries]
  max_series : Int
  max_samples : Int
}

///|
pub fn MetricRegistry::new(
  max_series? : Int = 512,
  max_samples? : Int = 1024,
) -> Result[MetricRegistry, ModbusError] {
  if max_series < 1 || max_samples < 1 {
    Err(InvalidData)
  } else {
    Ok({ series: [], max_series, max_samples })
  }
}

///|
pub fn MetricRegistry::series_count(self : MetricRegistry) -> Int {
  self.series.length()
}

///|
pub fn MetricRegistry::register(
  self : MetricRegistry,
  name : String,
  kind : MetricKind,
) -> Result[Unit, ModbusError] {
  if self.series.length() >= self.max_series {
    return Err(CapacityExceeded)
  }
  for existing in self.series {
    if existing.name() == name {
      return Err(InvalidData)
    }
  }
  let series = match MetricSeries::new(name, kind, capacity=self.max_samples) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.series.push(series)
  Ok(())
}

///|
pub fn MetricRegistry::has(self : MetricRegistry, name : String) -> Bool {
  for series in self.series {
    if series.name() == name {
      return true
    }
  }
  false
}

///|
pub fn MetricRegistry::record(
  self : MetricRegistry,
  metric : ServiceMetric,
) -> Result[Unit, ModbusError] {
  for series in self.series {
    if series.name() == metric.name() {
      return series.append(metric)
    }
  }
  if self.series.length() >= self.max_series {
    return Err(CapacityExceeded)
  }
  let series = match
    MetricSeries::new(metric.name(), metric.kind(), capacity=self.max_samples) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.series.push(series)
  self.series[self.series.length() - 1].append(metric)
}

///|
pub fn MetricRegistry::latest(
  self : MetricRegistry,
  name : String,
) -> ServiceMetric? {
  for series in self.series {
    if series.name() == name {
      return series.latest()
    }
  }
  None
}

///|
pub fn MetricRegistry::series(
  self : MetricRegistry,
  name : String,
) -> MetricSeries? {
  for series in self.series {
    if series.name() == name {
      return Some(series)
    }
  }
  None
}

///|
pub fn MetricRegistry::names(self : MetricRegistry) -> Array[String] {
  let result : Array[String] = []
  for series in self.series {
    result.push(series.name())
  }
  result
}

///|
/// Export a compact Prometheus-like line representation without external dependencies.
pub fn MetricRegistry::export_lines(self : MetricRegistry) -> Array[String] {
  let lines : Array[String] = []
  for series in self.series {
    match series.latest() {
      Some(metric) =>
        lines.push(
          metric.name() +
          "{kind=\"" +
          metric_kind_name(metric.kind()) +
          "\"} " +
          metric.value().to_string(),
        )
      None => ()
    }
  }
  lines
}

///|
/// Collect a time range from every registered series.
pub fn MetricRegistry::range(
  self : MetricRegistry,
  start : Int,
  end : Int,
) -> Result[Array[ServiceMetric], ModbusError] {
  if start < 0 || end < start {
    return Err(InvalidData)
  }
  let result : Array[ServiceMetric] = []
  for series in self.series {
    let values = match series.between(start, end) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    for value in values {
      result.push(value)
    }
  }
  Ok(result)
}

///|
/// Snapshot counts for a service status endpoint.
pub(all) struct ObservabilityDigest {
  metric_series : Int
  samples : Int
  counters : Int
  gauges : Int
  latest_timestamp : Int
}

///|
pub fn MetricRegistry::digest(self : MetricRegistry) -> ObservabilityDigest {
  let mut samples = 0
  let mut counters = 0
  let mut gauges = 0
  let mut latest = 0
  for series in self.series {
    samples += series.length()
    match series.kind() {
      CounterMetric => counters += 1
      GaugeMetric => gauges += 1
      _ => ()
    }
    match series.latest() {
      Some(metric) =>
        if metric.timestamp() > latest {
          latest = metric.timestamp()
        }
      None => ()
    }
  }
  {
    metric_series: self.series.length(),
    samples,
    counters,
    gauges,
    latest_timestamp: latest,
  }
}

///|
pub fn ObservabilityDigest::metric_series(self : ObservabilityDigest) -> Int {
  self.metric_series
}

///|
pub fn ObservabilityDigest::samples(self : ObservabilityDigest) -> Int {
  self.samples
}

///|
pub fn ObservabilityDigest::counters(self : ObservabilityDigest) -> Int {
  self.counters
}

///|
pub fn ObservabilityDigest::gauges(self : ObservabilityDigest) -> Int {
  self.gauges
}

///|
pub fn ObservabilityDigest::latest_timestamp(self : ObservabilityDigest) -> Int {
  self.latest_timestamp
}
