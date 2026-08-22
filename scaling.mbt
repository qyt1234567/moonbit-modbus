///|
/// Physical unit associated with an engineering value.
pub(all) enum EngineeringUnit {
  Unitless
  Percent
  Celsius
  Fahrenheit
  Pascal
  Kilopascal
  Volt
  Ampere
  Hertz
  Rpm
  Meter
  Millimeter
  LiterPerMinute
} derive(Debug, Eq)

///|
/// Quality assigned to a value after conversion and filtering.
pub(all) enum ReadingQuality {
  Good
  OutOfRange
  Stale
  Disconnected
  BadFormat
  Substituted
} derive(Debug, Eq)

///|
pub fn engineering_unit_name(unit : EngineeringUnit) -> String {
  match unit {
    Unitless => "unitless"
    Percent => "%"
    Celsius => "degC"
    Fahrenheit => "degF"
    Pascal => "Pa"
    Kilopascal => "kPa"
    Volt => "V"
    Ampere => "A"
    Hertz => "Hz"
    Rpm => "rpm"
    Meter => "m"
    Millimeter => "mm"
    LiterPerMinute => "L/min"
  }
}

///|
pub fn reading_quality_name(value : ReadingQuality) -> String {
  match value {
    Good => "good"
    OutOfRange => "out-of-range"
    Stale => "stale"
    Disconnected => "disconnected"
    BadFormat => "bad-format"
    Substituted => "substituted"
  }
}

///|
/// A deterministic integer scaling transform for register data.
pub(all) struct ScaleTransform {
  raw_min : Int
  raw_max : Int
  engineering_min : Int
  engineering_max : Int
  unit : EngineeringUnit
  deadband : Int
  clamp : Bool
  precision : Int
}

///|
pub fn ScaleTransform::new(
  raw_min : Int,
  raw_max : Int,
  engineering_min : Int,
  engineering_max : Int,
  unit? : EngineeringUnit = Unitless,
  deadband? : Int = 0,
  clamp? : Bool = true,
  precision? : Int = 1,
) -> Result[ScaleTransform, ModbusError] {
  if raw_min >= raw_max ||
    engineering_min > engineering_max ||
    deadband < 0 ||
    precision < 1 {
    Err(InvalidData)
  } else {
    Ok({
      raw_min,
      raw_max,
      engineering_min,
      engineering_max,
      unit,
      deadband,
      clamp,
      precision,
    })
  }
}

///|
pub fn ScaleTransform::raw_min(self : ScaleTransform) -> Int {
  self.raw_min
}

///|
pub fn ScaleTransform::raw_max(self : ScaleTransform) -> Int {
  self.raw_max
}

///|
pub fn ScaleTransform::engineering_min(self : ScaleTransform) -> Int {
  self.engineering_min
}

///|
pub fn ScaleTransform::engineering_max(self : ScaleTransform) -> Int {
  self.engineering_max
}

///|
pub fn ScaleTransform::unit(self : ScaleTransform) -> EngineeringUnit {
  self.unit
}

///|
pub fn ScaleTransform::deadband(self : ScaleTransform) -> Int {
  self.deadband
}

///|
pub fn ScaleTransform::precision(self : ScaleTransform) -> Int {
  self.precision
}

///|
pub fn ScaleTransform::raw_in_range(self : ScaleTransform, raw : Int) -> Bool {
  raw >= self.raw_min && raw <= self.raw_max
}

///|
pub fn ScaleTransform::engineering_in_range(
  self : ScaleTransform,
  value : Int,
) -> Bool {
  value >= self.engineering_min && value <= self.engineering_max
}

///|
pub fn ScaleTransform::clamp_raw(self : ScaleTransform, raw : Int) -> Int {
  if raw < self.raw_min {
    self.raw_min
  } else if raw > self.raw_max {
    self.raw_max
  } else {
    raw
  }
}

///|
pub fn ScaleTransform::clamp_engineering(
  self : ScaleTransform,
  value : Int,
) -> Int {
  if value < self.engineering_min {
    self.engineering_min
  } else if value > self.engineering_max {
    self.engineering_max
  } else {
    value
  }
}

///|
pub fn ScaleTransform::raw_to_engineering(
  self : ScaleTransform,
  raw : Int,
) -> Result[Int, ModbusError] {
  if !self.raw_in_range(raw) && !self.clamp {
    return Err(InvalidData)
  }
  let input = if self.clamp { self.clamp_raw(raw) } else { raw }
  let numerator = (input - self.raw_min) *
    (self.engineering_max - self.engineering_min)
  Ok(self.engineering_min + numerator / (self.raw_max - self.raw_min))
}

///|
pub fn ScaleTransform::engineering_to_raw(
  self : ScaleTransform,
  value : Int,
) -> Result[Int, ModbusError] {
  if !self.engineering_in_range(value) && !self.clamp {
    return Err(InvalidData)
  }
  let input = if self.clamp { self.clamp_engineering(value) } else { value }
  let numerator = (input - self.engineering_min) * (self.raw_max - self.raw_min)
  Ok(self.raw_min + numerator / (self.engineering_max - self.engineering_min))
}

///|
pub fn ScaleTransform::normalize(
  self : ScaleTransform,
  raw : Int,
) -> Result[Int, ModbusError] {
  if !self.raw_in_range(raw) && !self.clamp {
    return Err(InvalidData)
  }
  let input = if self.clamp { self.clamp_raw(raw) } else { raw }
  Ok((input - self.raw_min) * 10000 / (self.raw_max - self.raw_min))
}

///|
pub fn ScaleTransform::apply_deadband(
  self : ScaleTransform,
  previous : Int,
  current : Int,
) -> Int {
  if (current - previous).abs() <= self.deadband {
    previous
  } else {
    current
  }
}

///|
pub fn ScaleTransform::format(self : ScaleTransform, value : Int) -> String {
  value.to_string() + " " + engineering_unit_name(self.unit)
}

///|
pub fn ScaleTransform::summary(self : ScaleTransform) -> String {
  "raw=" +
  self.raw_min.to_string() +
  ".." +
  self.raw_max.to_string() +
  " engineering=" +
  self.engineering_min.to_string() +
  ".." +
  self.engineering_max.to_string() +
  " unit=" +
  engineering_unit_name(self.unit)
}

///|
/// A calibration sample used to build a piecewise-linear curve.
pub(all) struct CalibrationSample {
  raw : Int
  engineering : Int
}

///|
pub fn CalibrationSample::new(
  raw : Int,
  engineering : Int,
) -> CalibrationSample {
  { raw, engineering }
}

///|
pub fn CalibrationSample::raw(self : CalibrationSample) -> Int {
  self.raw
}

///|
pub fn CalibrationSample::engineering(self : CalibrationSample) -> Int {
  self.engineering
}

///|
/// A monotonic calibration curve for sensors with non-linear error.
pub(all) struct CalibrationCurve {
  samples : Array[CalibrationSample]
  max_samples : Int
  clamp : Bool
}

///|
pub fn CalibrationCurve::new(
  max_samples? : Int = 32,
  clamp? : Bool = true,
) -> Result[CalibrationCurve, ModbusError] {
  if max_samples < 2 {
    Err(CapacityExceeded)
  } else {
    Ok({ samples: [], max_samples, clamp })
  }
}

///|
pub fn CalibrationCurve::length(self : CalibrationCurve) -> Int {
  self.samples.length()
}

///|
pub fn CalibrationCurve::add(
  self : CalibrationCurve,
  sample : CalibrationSample,
) -> Result[Unit, ModbusError] {
  if self.samples.length() >= self.max_samples {
    return Err(CapacityExceeded)
  }
  for current in self.samples {
    if current.raw() == sample.raw() {
      return Err(InvalidData)
    }
    if current.raw() > sample.raw() {
      return Err(InvalidData)
    }
  }
  if self.samples.length() > 0 &&
    sample.raw() <= self.samples[self.samples.length() - 1].raw() {
    return Err(InvalidData)
  }
  self.samples.push(sample)
  Ok(())
}

///|
pub fn CalibrationCurve::sample(
  self : CalibrationCurve,
  index : Int,
) -> Result[CalibrationSample, ModbusError] {
  if index < 0 || index >= self.samples.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.samples[index])
  }
}

///|
pub fn CalibrationCurve::raw_min(
  self : CalibrationCurve,
) -> Result[Int, ModbusError] {
  if self.samples.length() == 0 {
    Err(Incomplete)
  } else {
    Ok(self.samples[0].raw())
  }
}

///|
pub fn CalibrationCurve::raw_max(
  self : CalibrationCurve,
) -> Result[Int, ModbusError] {
  if self.samples.length() == 0 {
    Err(Incomplete)
  } else {
    Ok(self.samples[self.samples.length() - 1].raw())
  }
}

///|
pub fn CalibrationCurve::convert(
  self : CalibrationCurve,
  raw : Int,
) -> Result[Int, ModbusError] {
  if self.samples.length() < 2 {
    return Err(Incomplete)
  }
  if raw < self.samples[0].raw() {
    if !self.clamp {
      return Err(InvalidData)
    }
    return Ok(self.samples[0].engineering())
  }
  if raw > self.samples[self.samples.length() - 1].raw() {
    if !self.clamp {
      return Err(InvalidData)
    }
    return Ok(self.samples[self.samples.length() - 1].engineering())
  }
  for index in 1..<self.samples.length() {
    let right = self.samples[index]
    if raw <= right.raw() {
      let left = self.samples[index - 1]
      let raw_span = right.raw() - left.raw()
      let value_span = right.engineering() - left.engineering()
      return Ok(left.engineering() + (raw - left.raw()) * value_span / raw_span)
    }
  }
  Err(InvalidData)
}

///|
pub fn CalibrationCurve::convert_many(
  self : CalibrationCurve,
  values : Array[Int],
) -> Result[Array[Int], ModbusError] {
  let result : Array[Int] = []
  for value in values {
    match self.convert(value) {
      Ok(converted) => result.push(converted)
      Err(error) => return Err(error)
    }
  }
  Ok(result)
}

///|
pub fn CalibrationCurve::snapshot(
  self : CalibrationCurve,
) -> Array[CalibrationSample] {
  let result : Array[CalibrationSample] = []
  for sample in self.samples {
    result.push(sample)
  }
  result
}

///|
/// A timestamped reading after scaling and quality assessment.
pub(all) struct ScaledReading {
  point_id : String
  raw : Int
  value : Int
  unit : EngineeringUnit
  quality : ReadingQuality
  timestamp : Int
}

///|
pub fn ScaledReading::new(
  point_id : String,
  raw : Int,
  transform : ScaleTransform,
  timestamp : Int,
) -> Result[ScaledReading, ModbusError] {
  if point_id == "" || timestamp < 0 {
    return Err(InvalidData)
  }
  let quality = if transform.raw_in_range(raw) { Good } else { OutOfRange }
  let value = match transform.raw_to_engineering(raw) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ point_id, raw, value, unit: transform.unit(), quality, timestamp })
}

///|
pub fn ScaledReading::point_id(self : ScaledReading) -> String {
  self.point_id
}

///|
pub fn ScaledReading::raw(self : ScaledReading) -> Int {
  self.raw
}

///|
pub fn ScaledReading::value(self : ScaledReading) -> Int {
  self.value
}

///|
pub fn ScaledReading::unit(self : ScaledReading) -> EngineeringUnit {
  self.unit
}

///|
pub fn ScaledReading::quality(self : ScaledReading) -> ReadingQuality {
  self.quality
}

///|
pub fn ScaledReading::timestamp(self : ScaledReading) -> Int {
  self.timestamp
}

///|
pub fn ScaledReading::with_quality(
  self : ScaledReading,
  quality : ReadingQuality,
) -> ScaledReading {
  { ..self, quality, }
}

///|
pub fn ScaledReading::summary(self : ScaledReading) -> String {
  self.point_id +
  "=" +
  self.value.to_string() +
  " " +
  engineering_unit_name(self.unit) +
  " raw=" +
  self.raw.to_string() +
  " quality=" +
  reading_quality_name(self.quality)
}

///|
/// Simple rate limiter for noisy integer signals.
pub(all) struct RateLimiter {
  max_delta : Int
  mut previous : Int?
}

///|
pub fn RateLimiter::new(max_delta : Int) -> Result[RateLimiter, ModbusError] {
  if max_delta < 0 {
    Err(InvalidData)
  } else {
    Ok({ max_delta, previous: None })
  }
}

///|
pub fn RateLimiter::max_delta(self : RateLimiter) -> Int {
  self.max_delta
}

///|
pub fn RateLimiter::apply(self : RateLimiter, value : Int) -> Int {
  match self.previous {
    None => {
      self.previous = Some(value)
      value
    }
    Some(previous) => {
      let delta = value - previous
      let output = if delta > self.max_delta {
        previous + self.max_delta
      } else if delta < -self.max_delta {
        previous - self.max_delta
      } else {
        value
      }
      self.previous = Some(output)
      output
    }
  }
}

///|
pub fn RateLimiter::reset(self : RateLimiter) -> Unit {
  self.previous = None
}

///|
/// Fixed-size moving average with integer arithmetic.
pub(all) struct MovingAverage {
  values : Array[Int]
  max_values : Int
}

///|
pub fn MovingAverage::new(
  max_values : Int,
) -> Result[MovingAverage, ModbusError] {
  if max_values < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ values: [], max_values })
  }
}

///|
pub fn MovingAverage::push(self : MovingAverage, value : Int) -> Unit {
  if self.values.length() >= self.max_values {
    ignore(self.values.remove(0))
  }
  self.values.push(value)
}

///|
pub fn MovingAverage::length(self : MovingAverage) -> Int {
  self.values.length()
}

///|
pub fn MovingAverage::average(self : MovingAverage) -> Result[Int, ModbusError] {
  if self.values.length() == 0 {
    return Err(Incomplete)
  }
  let mut sum = 0
  for value in self.values {
    sum += value
  }
  Ok(sum / self.values.length())
}

///|
pub fn MovingAverage::snapshot(self : MovingAverage) -> Array[Int] {
  let result : Array[Int] = []
  for value in self.values {
    result.push(value)
  }
  result
}

///|
pub fn MovingAverage::clear(self : MovingAverage) -> Unit {
  self.values.clear()
}
