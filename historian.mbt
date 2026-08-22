///|
/// Aggregation used when reducing samples for a dashboard or export.
pub(all) enum Aggregation {
  LastValue
  MinimumValue
  MaximumValue
  SumValue
  AverageValue
  CountValue
} derive(Debug, Eq)

///|
pub fn aggregation_name(value : Aggregation) -> String {
  match value {
    LastValue => "last"
    MinimumValue => "min"
    MaximumValue => "max"
    SumValue => "sum"
    AverageValue => "average"
    CountValue => "count"
  }
}

///|
/// One immutable historian sample.
pub(all) struct TagSample {
  point_id : String
  timestamp : Int
  value : Int
  quality : ReadingQuality
}

///|
pub fn TagSample::new(
  point_id : String,
  timestamp : Int,
  value : Int,
  quality? : ReadingQuality = Good,
) -> Result[TagSample, ModbusError] {
  if point_id == "" || timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ point_id, timestamp, value, quality })
  }
}

///|
pub fn TagSample::point_id(self : TagSample) -> String {
  self.point_id
}

///|
pub fn TagSample::timestamp(self : TagSample) -> Int {
  self.timestamp
}

///|
pub fn TagSample::value(self : TagSample) -> Int {
  self.value
}

///|
pub fn TagSample::quality(self : TagSample) -> ReadingQuality {
  self.quality
}

///|
pub fn TagSample::is_good(self : TagSample) -> Bool {
  self.quality == Good
}

///|
pub fn TagSample::summary(self : TagSample) -> String {
  self.point_id +
  " t=" +
  self.timestamp.to_string() +
  " value=" +
  self.value.to_string() +
  " quality=" +
  reading_quality_name(self.quality)
}

///|
/// A time range with samples belonging to one point.
pub(all) struct TagSeries {
  point_id : String
  samples : Array[TagSample]
  max_samples : Int
  mut dropped : Int
}

///|
pub fn TagSeries::new(
  point_id : String,
  max_samples? : Int = 8192,
) -> Result[TagSeries, ModbusError] {
  if point_id == "" || max_samples < 1 {
    Err(InvalidData)
  } else {
    Ok({ point_id, samples: [], max_samples, dropped: 0 })
  }
}

///|
pub fn TagSeries::point_id(self : TagSeries) -> String {
  self.point_id
}

///|
pub fn TagSeries::length(self : TagSeries) -> Int {
  self.samples.length()
}

///|
pub fn TagSeries::dropped(self : TagSeries) -> Int {
  self.dropped
}

///|
pub fn TagSeries::append(
  self : TagSeries,
  sample : TagSample,
) -> Result[Unit, ModbusError] {
  if sample.point_id() != self.point_id {
    return Err(UnitMismatch)
  }
  if self.samples.length() > 0 &&
    sample.timestamp() < self.samples[self.samples.length() - 1].timestamp() {
    return Err(InvalidData)
  }
  if self.samples.length() >= self.max_samples {
    ignore(self.samples.remove(0))
    self.dropped += 1
  }
  self.samples.push(sample)
  Ok(())
}

///|
pub fn TagSeries::at(
  self : TagSeries,
  index : Int,
) -> Result[TagSample, ModbusError] {
  if index < 0 || index >= self.samples.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.samples[index])
  }
}

///|
pub fn TagSeries::first(self : TagSeries) -> TagSample? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[0])
  }
}

///|
pub fn TagSeries::last(self : TagSeries) -> TagSample? {
  if self.samples.length() == 0 {
    None
  } else {
    Some(self.samples[self.samples.length() - 1])
  }
}

///|
pub fn TagSeries::between(
  self : TagSeries,
  start : Int,
  end : Int,
) -> Result[Array[TagSample], ModbusError] {
  if start < 0 || end < start {
    return Err(InvalidData)
  }
  let result : Array[TagSample] = []
  for sample in self.samples {
    if sample.timestamp() >= start && sample.timestamp() <= end {
      result.push(sample)
    }
  }
  Ok(result)
}

///|
pub fn TagSeries::good_count(self : TagSeries) -> Int {
  let mut count = 0
  for sample in self.samples {
    if sample.is_good() {
      count += 1
    }
  }
  count
}

///|
pub fn TagSeries::average(
  self : TagSeries,
  start : Int,
  end : Int,
) -> Result[Int, ModbusError] {
  let samples = match self.between(start, end) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if samples.length() == 0 {
    return Err(Incomplete)
  }
  let mut sum = 0
  let mut count = 0
  for sample in samples {
    if sample.is_good() {
      sum += sample.value()
      count += 1
    }
  }
  if count == 0 {
    Err(Incomplete)
  } else {
    Ok(sum / count)
  }
}

///|
pub fn TagSeries::aggregate(
  self : TagSeries,
  start : Int,
  end : Int,
  aggregation : Aggregation,
) -> Result[Int, ModbusError] {
  let samples = match self.between(start, end) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if samples.length() == 0 {
    return Err(Incomplete)
  }
  match aggregation {
    LastValue => Ok(samples[samples.length() - 1].value())
    CountValue => Ok(samples.length())
    AverageValue => {
      let mut sum = 0
      for sample in samples {
        sum += sample.value()
      }
      Ok(sum / samples.length())
    }
    MinimumValue => {
      let mut value = samples[0].value()
      for sample in samples {
        if sample.value() < value {
          value = sample.value()
        }
      }
      Ok(value)
    }
    MaximumValue => {
      let mut value = samples[0].value()
      for sample in samples {
        if sample.value() > value {
          value = sample.value()
        }
      }
      Ok(value)
    }
    SumValue => {
      let mut value = 0
      for sample in samples {
        value += sample.value()
      }
      Ok(value)
    }
  }
}

///|
pub fn TagSeries::snapshot(self : TagSeries) -> Array[TagSample] {
  let result : Array[TagSample] = []
  for sample in self.samples {
    result.push(sample)
  }
  result
}

///|
pub fn TagSeries::clear(self : TagSeries) -> Unit {
  self.samples.clear()
  self.dropped = 0
}

///|
pub fn TagSeries::summary(self : TagSeries) -> String {
  self.point_id +
  " samples=" +
  self.length().to_string() +
  " good=" +
  self.good_count().to_string() +
  " dropped=" +
  self.dropped.to_string()
}

///|
/// A bounded multi-point historian.
pub(all) struct Historian {
  series : Array[TagSeries]
  max_points : Int
  per_point_capacity : Int
}

///|
pub fn Historian::new(
  max_points? : Int = 256,
  per_point_capacity? : Int = 8192,
) -> Result[Historian, ModbusError] {
  if max_points < 1 || per_point_capacity < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ series: [], max_points, per_point_capacity })
  }
}

///|
pub fn Historian::point_count(self : Historian) -> Int {
  self.series.length()
}

///|
pub fn Historian::ensure_point(
  self : Historian,
  point_id : String,
) -> Result[Unit, ModbusError] {
  if point_id == "" {
    return Err(InvalidData)
  }
  for current in self.series {
    if current.point_id() == point_id {
      return Ok(())
    }
  }
  if self.series.length() >= self.max_points {
    return Err(CapacityExceeded)
  }
  self.series.push(
    TagSeries::new(point_id, max_samples=self.per_point_capacity).unwrap(),
  )
  Ok(())
}

///|
pub fn Historian::append(
  self : Historian,
  sample : TagSample,
) -> Result[Unit, ModbusError] {
  match self.ensure_point(sample.point_id()) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for series in self.series {
    if series.point_id() == sample.point_id() {
      return series.append(sample)
    }
  }
  Err(InvalidData)
}

///|
pub fn Historian::get(self : Historian, point_id : String) -> TagSeries? {
  for series in self.series {
    if series.point_id() == point_id {
      return Some(series)
    }
  }
  None
}

///|
pub fn Historian::query(
  self : Historian,
  point_id : String,
  start : Int,
  end : Int,
) -> Result[Array[TagSample], ModbusError] {
  match self.get(point_id) {
    Some(series) => series.between(start, end)
    None => Err(InvalidData)
  }
}

///|
pub fn Historian::aggregate(
  self : Historian,
  point_id : String,
  start : Int,
  end : Int,
  aggregation : Aggregation,
) -> Result[Int, ModbusError] {
  match self.get(point_id) {
    Some(series) => series.aggregate(start, end, aggregation)
    None => Err(InvalidData)
  }
}

///|
pub fn Historian::series_snapshot(self : Historian) -> Array[TagSeries] {
  let result : Array[TagSeries] = []
  for series in self.series {
    result.push(series)
  }
  result
}

///|
pub fn Historian::remove(
  self : Historian,
  point_id : String,
) -> Result[TagSeries, ModbusError] {
  for index, series in self.series {
    if series.point_id() == point_id {
      ignore(self.series.remove(index))
      return Ok(series)
    }
  }
  Err(InvalidData)
}

///|
pub fn Historian::clear(self : Historian) -> Unit {
  for series in self.series {
    series.clear()
  }
}

///|
pub fn Historian::total_samples(self : Historian) -> Int {
  let mut result = 0
  for series in self.series {
    result += series.length()
  }
  result
}

///|
pub fn Historian::summary(self : Historian) -> String {
  "points=" +
  self.point_count().to_string() +
  " samples=" +
  self.total_samples().to_string()
}

///|
/// A fixed interval bucket for downsampled exports.
pub(all) struct HistoryBucket {
  start : Int
  end : Int
  mut count : Int
  mut minimum : Int
  mut maximum : Int
  mut sum : Int
}

///|
pub fn HistoryBucket::new(
  start : Int,
  width : Int,
  first : Int,
) -> Result[HistoryBucket, ModbusError] {
  if start < 0 || width < 1 {
    Err(InvalidData)
  } else {
    Ok({
      start,
      end: start + width,
      count: 1,
      minimum: first,
      maximum: first,
      sum: first,
    })
  }
}

///|
pub fn HistoryBucket::start(self : HistoryBucket) -> Int {
  self.start
}

///|
pub fn HistoryBucket::end(self : HistoryBucket) -> Int {
  self.end
}

///|
pub fn HistoryBucket::count(self : HistoryBucket) -> Int {
  self.count
}

///|
pub fn HistoryBucket::minimum(self : HistoryBucket) -> Int {
  self.minimum
}

///|
pub fn HistoryBucket::maximum(self : HistoryBucket) -> Int {
  self.maximum
}

///|
pub fn HistoryBucket::average(self : HistoryBucket) -> Int {
  self.sum / self.count
}

///|
pub fn HistoryBucket::contains(self : HistoryBucket, timestamp : Int) -> Bool {
  timestamp >= self.start && timestamp < self.end
}

///|
pub fn HistoryBucket::add(self : HistoryBucket, value : Int) -> Unit {
  self.count += 1
  self.sum += value
  if value < self.minimum {
    self.minimum = value
  }
  if value > self.maximum {
    self.maximum = value
  }
}

///|
pub fn bucket_samples(
  samples : Array[TagSample],
  start : Int,
  width : Int,
) -> Result[Array[HistoryBucket], ModbusError] {
  if start < 0 || width < 1 {
    return Err(InvalidData)
  }
  let buckets : Array[HistoryBucket] = []
  for sample in samples {
    let index = (sample.timestamp() - start) / width
    if sample.timestamp() >= start {
      let bucket_start = start + index * width
      let mut found = false
      for bucket in buckets {
        if bucket.start() == bucket_start {
          bucket.add(sample.value())
          found = true
        }
      }
      if !found {
        buckets.push(
          HistoryBucket::new(bucket_start, width, sample.value()).unwrap(),
        )
      }
    }
  }
  Ok(buckets)
}
