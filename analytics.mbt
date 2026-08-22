///|
/// Direction of a value series over a configured observation window.
pub(all) enum TrendDirection {
  RisingTrend
  FallingTrend
  StableTrend
  InsufficientTrend
} derive(Debug, Eq)

///|
/// Reason a sample was flagged by an analytics rule.
pub(all) enum AnomalyKind {
  UpperLimitAnomaly
  LowerLimitAnomaly
  SpikeAnomaly
  FlatlineAnomaly
  RateAnomaly
} derive(Debug, Eq)

///|
/// A timestamped value used by trend and anomaly calculations.
pub(all) struct AnalyticsSample {
  timestamp : Int
  value : Int
  quality : ReadingQuality
}

///|
pub fn AnalyticsSample::new(
  timestamp : Int,
  value : Int,
  quality? : ReadingQuality = Good,
) -> Result[AnalyticsSample, ModbusError] {
  if timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ timestamp, value, quality })
  }
}

///|
pub fn AnalyticsSample::timestamp(self : AnalyticsSample) -> Int {
  self.timestamp
}

///|
pub fn AnalyticsSample::value(self : AnalyticsSample) -> Int {
  self.value
}

///|
pub fn AnalyticsSample::quality(self : AnalyticsSample) -> ReadingQuality {
  self.quality
}

///|
pub fn AnalyticsSample::usable(self : AnalyticsSample) -> Bool {
  self.quality == Good
}

///|
/// A bounded time series with deterministic order guarantees.
pub(all) struct AnalyticsWindow {
  id : String
  capacity : Int
  samples : Array[AnalyticsSample]
  mut dropped : Int
}

///|
pub fn AnalyticsWindow::new(
  id : String,
  capacity? : Int = 2048,
) -> Result[AnalyticsWindow, ModbusError] {
  if id == "" || capacity < 2 {
    Err(InvalidData)
  } else {
    Ok({ id, capacity, samples: [], dropped: 0 })
  }
}

///|
pub fn AnalyticsWindow::id(self : AnalyticsWindow) -> String {
  self.id
}

///|
pub fn AnalyticsWindow::capacity(self : AnalyticsWindow) -> Int {
  self.capacity
}

///|
pub fn AnalyticsWindow::length(self : AnalyticsWindow) -> Int {
  self.samples.length()
}

///|
pub fn AnalyticsWindow::dropped(self : AnalyticsWindow) -> Int {
  self.dropped
}

///|
pub fn AnalyticsWindow::append(
  self : AnalyticsWindow,
  sample : AnalyticsSample,
) -> Result[Unit, ModbusError] {
  if self.samples.length() > 0 &&
    sample.timestamp() < self.samples[self.samples.length() - 1].timestamp() {
    return Err(InvalidData)
  }
  if self.samples.length() >= self.capacity {
    ignore(self.samples.remove(0))
    self.dropped += 1
  }
  self.samples.push(sample)
  Ok(())
}

///|
pub fn AnalyticsWindow::at(
  self : AnalyticsWindow,
  index : Int,
) -> Result[AnalyticsSample, ModbusError] {
  if index < 0 || index >= self.samples.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.samples[index])
  }
}

///|
pub fn AnalyticsWindow::first(self : AnalyticsWindow) -> AnalyticsSample? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[0])
  }
}

///|
pub fn AnalyticsWindow::last(self : AnalyticsWindow) -> AnalyticsSample? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[self.samples.length() - 1])
  }
}

///|
pub fn AnalyticsWindow::usable_values(self : AnalyticsWindow) -> Array[Int] {
  let result : Array[Int] = []
  for sample in self.samples {
    if sample.usable() {
      result.push(sample.value())
    }
  }
  result
}

///|
pub fn AnalyticsWindow::minimum(
  self : AnalyticsWindow,
) -> Result[Int, ModbusError] {
  let values = self.usable_values()
  if values.length() == 0 {
    return Err(Incomplete)
  }
  let mut result = values[0]
  for value in values {
    if value < result {
      result = value
    }
  }
  Ok(result)
}

///|
pub fn AnalyticsWindow::maximum(
  self : AnalyticsWindow,
) -> Result[Int, ModbusError] {
  let values = self.usable_values()
  if values.length() == 0 {
    return Err(Incomplete)
  }
  let mut result = values[0]
  for value in values {
    if value > result {
      result = value
    }
  }
  Ok(result)
}

///|
pub fn AnalyticsWindow::average(
  self : AnalyticsWindow,
) -> Result[Int, ModbusError] {
  let values = self.usable_values()
  if values.length() == 0 {
    return Err(Incomplete)
  }
  let mut sum = 0
  for value in values {
    sum += value
  }
  Ok(sum / values.length())
}

///|
pub fn AnalyticsWindow::range(
  self : AnalyticsWindow,
) -> Result[Int, ModbusError] {
  let low = match self.minimum() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let high = match self.maximum() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(high - low)
}

///|
pub fn AnalyticsWindow::slope(
  self : AnalyticsWindow,
) -> Result[Int, ModbusError] {
  if self.samples.length() < 2 {
    return Err(Incomplete)
  }
  let first = self.samples[0]
  let last = self.samples[self.samples.length() - 1]
  let elapsed = last.timestamp() - first.timestamp()
  if elapsed == 0 {
    return Err(InvalidData)
  }
  Ok((last.value() - first.value()) * 1000 / elapsed)
}

///|
pub fn AnalyticsWindow::direction(
  self : AnalyticsWindow,
  threshold : Int,
) -> Result[TrendDirection, ModbusError] {
  if threshold < 0 {
    return Err(InvalidData)
  }
  let slope = match self.slope() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if slope > threshold {
    Ok(RisingTrend)
  } else if slope < -threshold {
    Ok(FallingTrend)
  } else {
    Ok(StableTrend)
  }
}

///|
/// A limit and deviation rule applied to a series.
pub(all) struct AnalyticsRule {
  id : String
  lower : Int?
  upper : Int?
  spike_delta : Int
  flatline_delta : Int
  flatline_count : Int
}

///|
pub fn AnalyticsRule::new(
  id : String,
  lower? : Int = 0,
  upper? : Int = 0,
  spike_delta? : Int = 0,
  flatline_delta? : Int = 0,
  flatline_count? : Int = 0,
) -> Result[AnalyticsRule, ModbusError] {
  if id == "" || spike_delta < 0 || flatline_delta < 0 || flatline_count < 0 {
    return Err(InvalidData)
  }
  let selected_lower = if lower == 0 { None } else { Some(lower) }
  let selected_upper = if upper == 0 { None } else { Some(upper) }
  match (selected_lower, selected_upper) {
    (Some(low), Some(high)) => if low >= high { return Err(InvalidData) }
    _ => ()
  }
  Ok({
    id,
    lower: selected_lower,
    upper: selected_upper,
    spike_delta,
    flatline_delta,
    flatline_count,
  })
}

///|
pub fn AnalyticsRule::id(self : AnalyticsRule) -> String {
  self.id
}

///|
pub fn AnalyticsRule::lower(self : AnalyticsRule) -> Int? {
  self.lower
}

///|
pub fn AnalyticsRule::upper(self : AnalyticsRule) -> Int? {
  self.upper
}

///|
pub fn AnalyticsRule::spike_delta(self : AnalyticsRule) -> Int {
  self.spike_delta
}

///|
pub fn AnalyticsRule::flatline_delta(self : AnalyticsRule) -> Int {
  self.flatline_delta
}

///|
pub fn AnalyticsRule::flatline_count(self : AnalyticsRule) -> Int {
  self.flatline_count
}

///|
/// A detected deviation with enough context for an incident message.
pub(all) struct ValueAnomaly {
  rule_id : String
  timestamp : Int
  value : Int
  kind : AnomalyKind
  severity : Int
  detail : String
}

///|
pub fn ValueAnomaly::new(
  rule_id : String,
  timestamp : Int,
  value : Int,
  kind : AnomalyKind,
  severity : Int,
  detail : String,
) -> Result[ValueAnomaly, ModbusError] {
  if rule_id == "" ||
    timestamp < 0 ||
    severity < 0 ||
    severity > 100 ||
    detail == "" {
    return Err(InvalidData)
  }
  Ok({ rule_id, timestamp, value, kind, severity, detail })
}

///|
pub fn ValueAnomaly::rule_id(self : ValueAnomaly) -> String {
  self.rule_id
}

///|
pub fn ValueAnomaly::timestamp(self : ValueAnomaly) -> Int {
  self.timestamp
}

///|
pub fn ValueAnomaly::value(self : ValueAnomaly) -> Int {
  self.value
}

///|
pub fn ValueAnomaly::kind(self : ValueAnomaly) -> AnomalyKind {
  self.kind
}

///|
pub fn ValueAnomaly::severity(self : ValueAnomaly) -> Int {
  self.severity
}

///|
pub fn ValueAnomaly::detail(self : ValueAnomaly) -> String {
  self.detail
}

///|
pub fn anomaly_kind_name(kind : AnomalyKind) -> String {
  match kind {
    UpperLimitAnomaly => "upper-limit"
    LowerLimitAnomaly => "lower-limit"
    SpikeAnomaly => "spike"
    FlatlineAnomaly => "flatline"
    RateAnomaly => "rate"
  }
}

///|
pub fn AnalyticsRule::evaluate(
  self : AnalyticsRule,
  window : AnalyticsWindow,
) -> Array[ValueAnomaly] {
  let result : Array[ValueAnomaly] = []
  for i in 0..<window.length() {
    let sample = match window.at(i) {
      Ok(value) => value
      Err(_) => continue
    }
    match self.upper {
      Some(limit) =>
        if sample.value() > limit {
          let detail = "value=" +
            sample.value().to_string() +
            " upper=" +
            limit.to_string()
          match
            ValueAnomaly::new(
              self.id,
              sample.timestamp(),
              sample.value(),
              UpperLimitAnomaly,
              80,
              detail,
            ) {
            Ok(value) => result.push(value)
            Err(_) => ()
          }
        }
      None => ()
    }
    match self.lower {
      Some(limit) =>
        if sample.value() < limit {
          let detail = "value=" +
            sample.value().to_string() +
            " lower=" +
            limit.to_string()
          match
            ValueAnomaly::new(
              self.id,
              sample.timestamp(),
              sample.value(),
              LowerLimitAnomaly,
              80,
              detail,
            ) {
            Ok(value) => result.push(value)
            Err(_) => ()
          }
        }
      None => ()
    }
    if i > 0 {
      let previous = match window.at(i - 1) {
        Ok(value) => value
        Err(_) => continue
      }
      if self.spike_delta > 0 &&
        (sample.value() - previous.value()).abs() >= self.spike_delta {
        let detail = "delta=" +
          (sample.value() - previous.value()).abs().to_string()
        match
          ValueAnomaly::new(
            self.id,
            sample.timestamp(),
            sample.value(),
            SpikeAnomaly,
            70,
            detail,
          ) {
          Ok(value) => result.push(value)
          Err(_) => ()
        }
      }
    }
  }
  if self.flatline_count > 1 && window.length() >= self.flatline_count {
    let start = window.length() - self.flatline_count
    let baseline = match window.at(start) {
      Ok(value) => value.value()
      Err(_) => 0
    }
    let mut flat = true
    for i in start..<window.length() {
      let value = match window.at(i) {
        Ok(sample) => sample.value()
        Err(_) => baseline
      }
      if (value - baseline).abs() > self.flatline_delta {
        flat = false
      }
    }
    if flat {
      let timestamp = match window.last() {
        Some(value) => value.timestamp()
        None => 0
      }
      match
        ValueAnomaly::new(
          self.id,
          timestamp,
          baseline,
          FlatlineAnomaly,
          50,
          "unchanged-series",
        ) {
        Ok(value) => result.push(value)
        Err(_) => ()
      }
    }
  }
  result
}

///|
/// Fixed-width histogram used for distribution and percentile approximations.
pub(all) struct ValueHistogram {
  lower : Int
  upper : Int
  width : Int
  bins : Array[Int]
  mut outside : Int
}

///|
pub fn ValueHistogram::new(
  lower : Int,
  upper : Int,
  bin_count : Int,
) -> Result[ValueHistogram, ModbusError] {
  if lower >= upper || bin_count < 1 {
    return Err(InvalidData)
  }
  let width = (upper - lower + bin_count - 1) / bin_count
  let bins : Array[Int] = []
  for _ in 0..<bin_count {
    bins.push(0)
  }
  Ok({ lower, upper, width, bins, outside: 0 })
}

///|
pub fn ValueHistogram::add(self : ValueHistogram, value : Int) -> Unit {
  if value < self.lower || value >= self.upper {
    self.outside += 1
  } else {
    let index = (value - self.lower) / self.width
    let safe = if index >= self.bins.length() {
      self.bins.length() - 1
    } else {
      index
    }
    self.bins[safe] += 1
  }
}

///|
pub fn ValueHistogram::bins(self : ValueHistogram) -> Array[Int] {
  self.bins
}

///|
pub fn ValueHistogram::outside(self : ValueHistogram) -> Int {
  self.outside
}

///|
pub fn ValueHistogram::total(self : ValueHistogram) -> Int {
  let mut sum = self.outside
  for count in self.bins {
    sum += count
  }
  sum
}

///|
pub fn ValueHistogram::percentile(
  self : ValueHistogram,
  percent : Int,
) -> Result[Int, ModbusError] {
  if percent < 0 || percent > 100 || self.total() == 0 {
    return Err(InvalidData)
  }
  let target = (self.total() * percent + 99) / 100
  let mut seen = 0
  for i in 0..<self.bins.length() {
    seen += self.bins[i]
    if seen >= target {
      return Ok(self.lower + i * self.width)
    }
  }
  Ok(self.upper - 1)
}

///|
/// Combined trend and distribution report.
pub(all) struct AnalyticsReport {
  direction : TrendDirection
  average : Int
  minimum : Int
  maximum : Int
  slope : Int
  anomalies : Int
  p95 : Int
}

///|
pub fn analytics_report(
  window : AnalyticsWindow,
  rule : AnalyticsRule,
  histogram : ValueHistogram,
) -> Result[AnalyticsReport, ModbusError] {
  let average = match window.average() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let minimum = match window.minimum() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let maximum = match window.maximum() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let slope = match window.slope() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let direction = match window.direction(5) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let anomalies = rule.evaluate(window).length()
  let p95 = match histogram.percentile(95) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ direction, average, minimum, maximum, slope, anomalies, p95 })
}

///|
pub fn trend_direction_name(direction : TrendDirection) -> String {
  match direction {
    RisingTrend => "rising"
    FallingTrend => "falling"
    StableTrend => "stable"
    InsufficientTrend => "insufficient"
  }
}

///|
pub fn AnalyticsReport::direction(self : AnalyticsReport) -> TrendDirection {
  self.direction
}

///|
pub fn AnalyticsReport::average(self : AnalyticsReport) -> Int {
  self.average
}

///|
pub fn AnalyticsReport::minimum(self : AnalyticsReport) -> Int {
  self.minimum
}

///|
pub fn AnalyticsReport::maximum(self : AnalyticsReport) -> Int {
  self.maximum
}

///|
pub fn AnalyticsReport::slope(self : AnalyticsReport) -> Int {
  self.slope
}

///|
pub fn AnalyticsReport::anomalies(self : AnalyticsReport) -> Int {
  self.anomalies
}

///|
pub fn AnalyticsReport::p95(self : AnalyticsReport) -> Int {
  self.p95
}
