///|
/// Direction of a frame in a transport capture.
pub(all) enum CaptureDirection {
  Received
  Transmitted
  Internal
} derive(Debug, Eq)

///|
/// Integrity state retained with a captured byte sequence.
pub(all) enum CaptureStatus {
  Decoded
  Undecoded
  Corrupt
  Truncated
} derive(Debug, Eq)

///|
/// A single timestamped wire record.
pub(all) struct CaptureRecord {
  id : Int
  timestamp : Int
  mode : Mode
  transaction_id : UInt16
  direction : CaptureDirection
  bytes : Array[Byte]
  frame : Frame?
  status : CaptureStatus
  note : String
}

///|
pub fn CaptureRecord::new(
  id : Int,
  timestamp : Int,
  mode : Mode,
  transaction_id : UInt16,
  direction : CaptureDirection,
  bytes : Array[Byte],
  note? : String = "",
) -> Result[CaptureRecord, ModbusError] {
  if id < 0 ||
    timestamp < 0 ||
    bytes.length() == 0 ||
    bytes.length() > limits_for(mode).max_adu {
    return Err(InvalidLength)
  }
  let decoded = decode_transaction(mode, bytes)
  match decoded {
    Ok((observed_id, frame)) =>
      Ok({
        id,
        timestamp,
        mode,
        transaction_id: if mode == Tcp {
          observed_id
        } else {
          transaction_id
        },
        direction,
        bytes: copy_bytes(bytes),
        frame: Some(frame),
        status: Decoded,
        note,
      })
    Err(InvalidChecksum) | Err(InvalidAscii) | Err(InvalidMbap) =>
      Ok({
        id,
        timestamp,
        mode,
        transaction_id,
        direction,
        bytes: copy_bytes(bytes),
        frame: None,
        status: Corrupt,
        note,
      })
    Err(Incomplete) =>
      Ok({
        id,
        timestamp,
        mode,
        transaction_id,
        direction,
        bytes: copy_bytes(bytes),
        frame: None,
        status: Truncated,
        note,
      })
    Err(_) =>
      Ok({
        id,
        timestamp,
        mode,
        transaction_id,
        direction,
        bytes: copy_bytes(bytes),
        frame: None,
        status: Undecoded,
        note,
      })
  }
}

///|
pub fn CaptureRecord::from_frame(
  id : Int,
  timestamp : Int,
  mode : Mode,
  transaction_id : UInt16,
  direction : CaptureDirection,
  frame : Frame,
  note? : String = "",
) -> Result[CaptureRecord, ModbusError] {
  let bytes = encode_mode(mode, frame)
  match
    CaptureRecord::new(
      id,
      timestamp,
      mode,
      transaction_id,
      direction,
      bytes,
      note~,
    ) {
    Ok(record) => Ok(record)
    Err(error) => Err(error)
  }
}

///|
pub fn CaptureRecord::id(self : CaptureRecord) -> Int {
  self.id
}

///|
pub fn CaptureRecord::timestamp(self : CaptureRecord) -> Int {
  self.timestamp
}

///|
pub fn CaptureRecord::mode(self : CaptureRecord) -> Mode {
  self.mode
}

///|
pub fn CaptureRecord::transaction_id(self : CaptureRecord) -> UInt16 {
  self.transaction_id
}

///|
pub fn CaptureRecord::direction(self : CaptureRecord) -> CaptureDirection {
  self.direction
}

///|
pub fn CaptureRecord::status(self : CaptureRecord) -> CaptureStatus {
  self.status
}

///|
pub fn CaptureRecord::note(self : CaptureRecord) -> String {
  self.note
}

///|
pub fn CaptureRecord::bytes(self : CaptureRecord) -> Array[Byte] {
  copy_bytes(self.bytes)
}

///|
pub fn CaptureRecord::frame(self : CaptureRecord) -> Frame? {
  self.frame
}

///|
pub fn CaptureRecord::unit_id(self : CaptureRecord) -> Byte? {
  match self.frame {
    Some(frame) => Some(frame.unit_id)
    None => None
  }
}

///|
pub fn CaptureRecord::function(self : CaptureRecord) -> Byte? {
  match self.frame {
    Some(frame) => Some(frame.pdu.function)
    None => None
  }
}

///|
pub fn CaptureRecord::is_valid(self : CaptureRecord) -> Bool {
  self.status == Decoded
}

///|
pub fn CaptureRecord::summary(self : CaptureRecord) -> String {
  "#" +
  self.id.to_string() +
  " t=" +
  self.timestamp.to_string() +
  " " +
  mode_name(self.mode) +
  " " +
  capture_status_name(self.status) +
  " bytes=" +
  self.bytes.length().to_string()
}

///|
pub fn capture_status_name(status : CaptureStatus) -> String {
  match status {
    Decoded => "decoded"
    Undecoded => "undecoded"
    Corrupt => "corrupt"
    Truncated => "truncated"
  }
}

///|
pub fn capture_direction_name(direction : CaptureDirection) -> String {
  match direction {
    Received => "rx"
    Transmitted => "tx"
    Internal => "internal"
  }
}

///|
/// Filter used to query a capture ring without decoding records again.
pub(all) struct CaptureFilter {
  mode : Mode?
  unit_id : Byte?
  function : Byte?
  direction : CaptureDirection?
  status : CaptureStatus?
  start_time : Int?
  end_time : Int?
}

///|
pub fn CaptureFilter::new() -> CaptureFilter {
  {
    mode: None,
    unit_id: None,
    function: None,
    direction: None,
    status: None,
    start_time: None,
    end_time: None,
  }
}

///|
pub fn CaptureFilter::with_mode(
  self : CaptureFilter,
  mode : Mode,
) -> CaptureFilter {
  { ..self, mode: Some(mode) }
}

///|
pub fn CaptureFilter::with_unit(
  self : CaptureFilter,
  unit_id : Byte,
) -> CaptureFilter {
  { ..self, unit_id: Some(unit_id) }
}

///|
pub fn CaptureFilter::with_function(
  self : CaptureFilter,
  function : Byte,
) -> CaptureFilter {
  { ..self, function: Some(function) }
}

///|
pub fn CaptureFilter::with_direction(
  self : CaptureFilter,
  direction : CaptureDirection,
) -> CaptureFilter {
  { ..self, direction: Some(direction) }
}

///|
pub fn CaptureFilter::with_status(
  self : CaptureFilter,
  status : CaptureStatus,
) -> CaptureFilter {
  { ..self, status: Some(status) }
}

///|
pub fn CaptureFilter::between(
  self : CaptureFilter,
  start : Int,
  end : Int,
) -> Result[CaptureFilter, ModbusError] {
  if start < 0 || end < start {
    Err(InvalidData)
  } else {
    Ok({ ..self, start_time: Some(start), end_time: Some(end) })
  }
}

///|
pub fn CaptureFilter::matches(
  self : CaptureFilter,
  record : CaptureRecord,
) -> Bool {
  let mode_ok = match self.mode {
    Some(mode) => record.mode() == mode
    None => true
  }
  let unit_ok = match (self.unit_id, record.unit_id()) {
    (Some(unit), Some(actual)) => unit == actual
    (Some(_), None) => false
    (None, _) => true
  }
  let function_ok = match (self.function, record.function()) {
    (Some(function), Some(actual)) =>
      function == actual || function == ordinary_function(actual)
    (Some(_), None) => false
    (None, _) => true
  }
  let direction_ok = match self.direction {
    Some(direction) => record.direction() == direction
    None => true
  }
  let status_ok = match self.status {
    Some(status) => record.status() == status
    None => true
  }
  let start_ok = match self.start_time {
    Some(start) => record.timestamp() >= start
    None => true
  }
  let end_ok = match self.end_time {
    Some(end) => record.timestamp() <= end
    None => true
  }
  mode_ok &&
  unit_ok &&
  function_ok &&
  direction_ok &&
  status_ok &&
  start_ok &&
  end_ok
}

///|
/// A bounded rolling store for protocol captures.
pub(all) struct CaptureRing {
  records : Array[CaptureRecord]
  max_records : Int
  mut next_id : Int
  mut lost : Int
}

///|
pub fn CaptureRing::new(
  max_records? : Int = 4096,
) -> Result[CaptureRing, ModbusError] {
  if max_records < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ records: [], max_records, next_id: 1, lost: 0 })
  }
}

///|
pub fn CaptureRing::length(self : CaptureRing) -> Int {
  self.records.length()
}

///|
pub fn CaptureRing::capacity(self : CaptureRing) -> Int {
  self.max_records
}

///|
pub fn CaptureRing::lost(self : CaptureRing) -> Int {
  self.lost
}

///|
pub fn CaptureRing::push(
  self : CaptureRing,
  timestamp : Int,
  mode : Mode,
  transaction_id : UInt16,
  direction : CaptureDirection,
  bytes : Array[Byte],
  note? : String = "",
) -> Result[CaptureRecord, ModbusError] {
  let record = match
    CaptureRecord::new(
      self.next_id,
      timestamp,
      mode,
      transaction_id,
      direction,
      bytes,
      note~,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.next_id += 1
  if self.records.length() >= self.max_records {
    ignore(self.records.remove(0))
    self.lost += 1
  }
  self.records.push(record)
  Ok(record)
}

///|
pub fn CaptureRing::push_frame(
  self : CaptureRing,
  timestamp : Int,
  mode : Mode,
  transaction_id : UInt16,
  direction : CaptureDirection,
  frame : Frame,
  note? : String = "",
) -> Result[CaptureRecord, ModbusError] {
  let bytes = encode_mode(mode, frame)
  self.push(timestamp, mode, transaction_id, direction, bytes, note~)
}

///|
pub fn CaptureRing::get(
  self : CaptureRing,
  index : Int,
) -> Result[CaptureRecord, ModbusError] {
  if index < 0 || index >= self.records.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.records[index])
  }
}

///|
pub fn CaptureRing::latest(self : CaptureRing) -> CaptureRecord? {
  if self.records.length() == 0 {
    None
  } else {
    Some(self.records[self.records.length() - 1])
  }
}

///|
pub fn CaptureRing::snapshot(self : CaptureRing) -> Array[CaptureRecord] {
  let result : Array[CaptureRecord] = []
  for record in self.records {
    result.push(record)
  }
  result
}

///|
pub fn CaptureRing::query(
  self : CaptureRing,
  filter : CaptureFilter,
) -> Array[CaptureRecord] {
  let result : Array[CaptureRecord] = []
  for record in self.records {
    if filter.matches(record) {
      result.push(record)
    }
  }
  result
}

///|
pub fn CaptureRing::clear(self : CaptureRing) -> Unit {
  self.records.clear()
  self.lost = 0
}

///|
pub fn CaptureRing::decoded_count(self : CaptureRing) -> Int {
  let mut count = 0
  for record in self.records {
    if record.status() == Decoded {
      count += 1
    }
  }
  count
}

///|
pub fn CaptureRing::corrupt_count(self : CaptureRing) -> Int {
  let mut count = 0
  for record in self.records {
    if record.status() == Corrupt {
      count += 1
    }
  }
  count
}

///|
pub fn CaptureRing::byte_count(self : CaptureRing) -> Int {
  let mut count = 0
  for record in self.records {
    count += record.bytes().length()
  }
  count
}

///|
pub fn CaptureRing::summary(self : CaptureRing) -> String {
  "records=" +
  self.length().to_string() +
  " bytes=" +
  self.byte_count().to_string() +
  " decoded=" +
  self.decoded_count().to_string() +
  " lost=" +
  self.lost.to_string()
}

///|
/// A deterministic replay item generated from a capture record.
pub(all) struct ReplayItem {
  record_id : Int
  mut due_at : Int
  bytes : Array[Byte]
  mut attempts : Int
  mut sent : Bool
}

///|
pub fn ReplayItem::new(
  record : CaptureRecord,
  due_at : Int,
) -> Result[ReplayItem, ModbusError] {
  if due_at < 0 {
    Err(InvalidData)
  } else {
    Ok({
      record_id: record.id(),
      due_at,
      bytes: record.bytes(),
      attempts: 0,
      sent: false,
    })
  }
}

///|
pub fn ReplayItem::record_id(self : ReplayItem) -> Int {
  self.record_id
}

///|
pub fn ReplayItem::due_at(self : ReplayItem) -> Int {
  self.due_at
}

///|
pub fn ReplayItem::bytes(self : ReplayItem) -> Array[Byte] {
  copy_bytes(self.bytes)
}

///|
pub fn ReplayItem::attempts(self : ReplayItem) -> Int {
  self.attempts
}

///|
pub fn ReplayItem::sent(self : ReplayItem) -> Bool {
  self.sent
}

///|
pub fn ReplayItem::is_due(self : ReplayItem, now : Int) -> Bool {
  !self.sent && now >= self.due_at
}

///|
pub fn ReplayItem::mark_sent(self : ReplayItem) -> Result[Unit, ModbusError] {
  if self.sent {
    Err(InvalidData)
  } else {
    self.attempts += 1
    self.sent = true
    Ok(())
  }
}

///|
pub fn ReplayItem::reset(
  self : ReplayItem,
  due_at : Int,
) -> Result[Unit, ModbusError] {
  if due_at < 0 {
    return Err(InvalidData)
  }
  self.due_at = due_at
  self.attempts = 0
  self.sent = false
  Ok(())
}

///|
/// A replay plan for deterministic integration tests and diagnostics.
pub(all) struct ReplayPlan {
  items : Array[ReplayItem]
  max_items : Int
  mut started_at : Int?
}

///|
pub fn ReplayPlan::new(
  max_items? : Int = 1024,
) -> Result[ReplayPlan, ModbusError] {
  if max_items < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ items: [], max_items, started_at: None })
  }
}

///|
pub fn ReplayPlan::add(
  self : ReplayPlan,
  record : CaptureRecord,
  delay : Int,
) -> Result[Unit, ModbusError] {
  if delay < 0 || self.items.length() >= self.max_items {
    return Err(CapacityExceeded)
  }
  let start = match self.started_at {
    Some(value) => value
    None => 0
  }
  match ReplayItem::new(record, start + delay) {
    Ok(item) => {
      self.items.push(item)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
pub fn ReplayPlan::length(self : ReplayPlan) -> Int {
  self.items.length()
}

///|
pub fn ReplayPlan::start(
  self : ReplayPlan,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 {
    Err(InvalidData)
  } else {
    self.started_at = Some(timestamp)
    Ok(())
  }
}

///|
pub fn ReplayPlan::next_due(self : ReplayPlan, now : Int) -> ReplayItem? {
  for item in self.items {
    if item.is_due(now) {
      return Some(item)
    }
  }
  None
}

///|
pub fn ReplayPlan::mark_sent(
  self : ReplayPlan,
  record_id : Int,
) -> Result[Unit, ModbusError] {
  for index, item in self.items {
    if item.record_id() == record_id {
      match item.mark_sent() {
        Ok(_) => {
          self.items[index] = item
          return Ok(())
        }
        Err(error) => return Err(error)
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn ReplayPlan::pending(self : ReplayPlan) -> Int {
  let mut count = 0
  for item in self.items {
    if !item.sent() {
      count += 1
    }
  }
  count
}

///|
pub fn ReplayPlan::completed(self : ReplayPlan) -> Int {
  self.length() - self.pending()
}

///|
pub fn ReplayPlan::snapshot(self : ReplayPlan) -> Array[ReplayItem] {
  let result : Array[ReplayItem] = []
  for item in self.items {
    result.push(item)
  }
  result
}

///|
pub fn ReplayPlan::reset(
  self : ReplayPlan,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  self.started_at = Some(timestamp)
  for index, item in self.items {
    match item.reset(timestamp) {
      Ok(_) => self.items[index] = item
      Err(error) => return Err(error)
    }
  }
  Ok(())
}
