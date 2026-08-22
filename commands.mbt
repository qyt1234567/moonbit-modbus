///|
/// Kind of operator command accepted by the control plane.
pub(all) enum DeviceCommandKind {
  WriteCoilCommand
  WriteRegisterCommand
  WriteCoilsCommand
  WriteRegistersCommand
  ReadVerificationCommand
  ClearAlarmCommand
  RestartDeviceCommand
  CustomCommand
} derive(Debug, Eq)

///|
/// Lifecycle of a command from admission to audit completion.
pub(all) enum DeviceCommandState {
  Queued
  Validating
  Dispatched
  Acknowledged
  Rejected
  TimedOut
  FailedCommand
  CancelledCommand
} derive(Debug, Eq)

///|
/// A typed key/value argument supplied by a UI, rule, or automation.
pub(all) struct CommandArgument {
  key : String
  value : String
}

///|
pub fn CommandArgument::new(
  key : String,
  value : String,
) -> Result[CommandArgument, ModbusError] {
  if key == "" {
    Err(InvalidData)
  } else {
    Ok({ key, value })
  }
}

///|
pub fn CommandArgument::key(self : CommandArgument) -> String {
  self.key
}

///|
pub fn CommandArgument::value(self : CommandArgument) -> String {
  self.value
}

///|
pub fn CommandArgument::as_int(
  self : CommandArgument,
) -> Result[Int, ModbusError] {
  Ok(@string.parse_int(self.value)) catch {
    _ => Err(InvalidData)
  }
}

///|
pub fn CommandArgument::as_bool(
  self : CommandArgument,
) -> Result[Bool, ModbusError] {
  if self.value == "true" || self.value == "1" {
    Ok(true)
  } else if self.value == "false" || self.value == "0" {
    Ok(false)
  } else {
    Err(InvalidData)
  }
}

///|
/// Definition and authorization context for one device operation.
pub(all) struct DeviceCommand {
  id : String
  device_id : String
  unit_id : Byte
  kind : DeviceCommandKind
  function : Byte
  address : UInt16
  quantity : Int
  arguments : Array[CommandArgument]
  principal : String
  reason : String
  timeout : Int
  mut state : DeviceCommandState
  mut created_at : Int
}

///|
pub fn DeviceCommand::new(
  id : String,
  device_id : String,
  unit_id : Byte,
  kind : DeviceCommandKind,
  function : Byte,
  address : UInt16,
  quantity : Int,
  principal : String,
  reason : String,
  created_at : Int,
  timeout? : Int = 3000,
) -> Result[DeviceCommand, ModbusError] {
  if id == "" || device_id == "" || principal == "" || reason == "" {
    return Err(InvalidData)
  }
  if !is_valid_unit_id(unit_id) ||
    function == 0 ||
    quantity < 1 ||
    timeout < 1 ||
    created_at < 0 {
    return Err(InvalidData)
  }
  Ok({
    id,
    device_id,
    unit_id,
    kind,
    function,
    address,
    quantity,
    arguments: [],
    principal,
    reason,
    timeout,
    state: Queued,
    created_at,
  })
}

///|
pub fn DeviceCommand::id(self : DeviceCommand) -> String {
  self.id
}

///|
pub fn DeviceCommand::device_id(self : DeviceCommand) -> String {
  self.device_id
}

///|
pub fn DeviceCommand::unit_id(self : DeviceCommand) -> Byte {
  self.unit_id
}

///|
pub fn DeviceCommand::kind(self : DeviceCommand) -> DeviceCommandKind {
  self.kind
}

///|
pub fn DeviceCommand::function(self : DeviceCommand) -> Byte {
  self.function
}

///|
pub fn DeviceCommand::address(self : DeviceCommand) -> UInt16 {
  self.address
}

///|
pub fn DeviceCommand::quantity(self : DeviceCommand) -> Int {
  self.quantity
}

///|
pub fn DeviceCommand::principal(self : DeviceCommand) -> String {
  self.principal
}

///|
pub fn DeviceCommand::reason(self : DeviceCommand) -> String {
  self.reason
}

///|
pub fn DeviceCommand::timeout(self : DeviceCommand) -> Int {
  self.timeout
}

///|
pub fn DeviceCommand::state(self : DeviceCommand) -> DeviceCommandState {
  self.state
}

///|
pub fn DeviceCommand::created_at(self : DeviceCommand) -> Int {
  self.created_at
}

///|
pub fn DeviceCommand::argument_count(self : DeviceCommand) -> Int {
  self.arguments.length()
}

///|
pub fn DeviceCommand::argument(
  self : DeviceCommand,
  key : String,
) -> CommandArgument? {
  for argument in self.arguments {
    if argument.key() == key {
      return Some(argument)
    }
  }
  None
}

///|
pub fn DeviceCommand::add_argument(
  self : DeviceCommand,
  argument : CommandArgument,
) -> Result[Unit, ModbusError] {
  for existing in self.arguments {
    if existing.key() == argument.key() {
      return Err(InvalidData)
    }
  }
  if self.arguments.length() >= 16 {
    return Err(CapacityExceeded)
  }
  self.arguments.push(argument)
  Ok(())
}

///|
pub fn DeviceCommand::set_state(
  self : DeviceCommand,
  state : DeviceCommandState,
) -> Result[Unit, ModbusError] {
  match (self.state, state) {
    (Queued, Validating) | (Queued, CancelledCommand) => ()
    (Validating, Dispatched)
    | (Validating, Rejected)
    | (Validating, CancelledCommand) => ()
    (Dispatched, Acknowledged)
    | (Dispatched, TimedOut)
    | (Dispatched, FailedCommand) => ()
    (_, _) => return Err(Busy)
  }
  self.state = state
  Ok(())
}

///|
pub fn DeviceCommand::is_terminal(self : DeviceCommand) -> Bool {
  match self.state {
    Acknowledged | Rejected | TimedOut | FailedCommand | CancelledCommand =>
      true
    _ => false
  }
}

///|
pub fn DeviceCommand::is_write(self : DeviceCommand) -> Bool {
  match self.kind {
    WriteCoilCommand
    | WriteRegisterCommand
    | WriteCoilsCommand
    | WriteRegistersCommand => true
    _ => false
  }
}

///|
pub fn DeviceCommand::verify_address(self : DeviceCommand) -> Bool {
  self.address.to_int() + self.quantity <= 65536 && self.quantity <= 123
}

///|
/// Build a PDU for commands represented directly by standard Modbus writes.
pub fn DeviceCommand::request(
  self : DeviceCommand,
) -> Result[Frame, ModbusError] {
  if !self.verify_address() {
    return Err(InvalidAddress)
  }
  match self.kind {
    WriteCoilCommand => {
      let argument = match self.argument("value") {
        Some(value) => value
        None => return Err(InvalidData)
      }
      let value = match argument.as_bool() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let data : Array[Byte] = [
        (self.address >> 8).to_byte(),
        self.address.to_byte(),
        if value {
          255
        } else {
          0
        },
        0,
      ]
      Ok(Frame::new(self.unit_id, 5, data))
    }
    WriteRegisterCommand => {
      let argument = match self.argument("value") {
        Some(value) => value
        None => return Err(InvalidData)
      }
      let value = match argument.as_int() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if value < 0 || value > 65535 {
        return Err(InvalidData)
      }
      let data : Array[Byte] = [
        (self.address >> 8).to_byte(),
        self.address.to_byte(),
        (value / 256).to_byte(),
        value.to_byte(),
      ]
      Ok(Frame::new(self.unit_id, 6, data))
    }
    WriteCoilsCommand => {
      let bytes = match self.argument("bytes") {
        Some(value) => value.value()
        None => return Err(InvalidData)
      }
      let parsed = command_parse_hex(bytes)
      if parsed.length() == 0 || parsed.length() > 250 {
        return Err(InvalidByteCount)
      }
      let data : Array[Byte] = [
        (self.address >> 8).to_byte(),
        self.address.to_byte(),
        (self.quantity / 256).to_byte(),
        self.quantity.to_byte(),
        parsed.length().to_byte(),
      ]
      for byte in parsed {
        data.push(byte)
      }
      Ok(Frame::new(self.unit_id, 15, data))
    }
    WriteRegistersCommand => {
      let bytes = match self.argument("bytes") {
        Some(value) => value.value()
        None => return Err(InvalidData)
      }
      let parsed = command_parse_hex(bytes)
      if parsed.length() == 0 ||
        parsed.length() > 246 ||
        parsed.length() != self.quantity * 2 {
        return Err(InvalidByteCount)
      }
      let data : Array[Byte] = [
        (self.address >> 8).to_byte(),
        self.address.to_byte(),
        (self.quantity / 256).to_byte(),
        self.quantity.to_byte(),
        parsed.length().to_byte(),
      ]
      for byte in parsed {
        data.push(byte)
      }
      Ok(Frame::new(self.unit_id, 16, data))
    }
    ReadVerificationCommand => {
      let data : Array[Byte] = [
        (self.address >> 8).to_byte(),
        self.address.to_byte(),
        (self.quantity / 256).to_byte(),
        self.quantity.to_byte(),
      ]
      Ok(Frame::new(self.unit_id, self.function, data))
    }
    _ => Err(Unsupported)
  }
}

///|
fn command_parse_hex(value : String) -> Array[Byte] {
  let result : Array[Byte] = []
  let mut high : Byte? = None
  for character in value.to_array() {
    let byte = character.to_int().to_byte()
    let nibble = match command_hex_nibble(byte) {
      Some(value) => value
      None => continue
    }
    match high {
      None => high = Some(nibble)
      Some(first) => {
        result.push(first * 16 + nibble)
        high = None
      }
    }
  }
  result
}

///|
fn command_hex_nibble(value : Byte) -> Byte? {
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
pub fn device_command_kind_name(kind : DeviceCommandKind) -> String {
  match kind {
    WriteCoilCommand => "write-coil"
    WriteRegisterCommand => "write-register"
    WriteCoilsCommand => "write-coils"
    WriteRegistersCommand => "write-registers"
    ReadVerificationCommand => "read-verification"
    ClearAlarmCommand => "clear-alarm"
    RestartDeviceCommand => "restart-device"
    CustomCommand => "custom"
  }
}

///|
pub fn device_command_state_name(state : DeviceCommandState) -> String {
  match state {
    Queued => "queued"
    Validating => "validating"
    Dispatched => "dispatched"
    Acknowledged => "acknowledged"
    Rejected => "rejected"
    TimedOut => "timed-out"
    FailedCommand => "failed"
    CancelledCommand => "cancelled"
  }
}

///|
/// Result returned by a transport or a simulated execution backend.
pub(all) struct CommandExecution {
  command_id : String
  state : DeviceCommandState
  started_at : Int
  finished_at : Int
  response : Frame?
  error : ModbusError?
  message : String
}

///|
pub fn CommandExecution::new(
  command_id : String,
  state : DeviceCommandState,
  started_at : Int,
  finished_at : Int,
  response? : Frame = Frame::new(0, 0, []),
  error? : ModbusError = Incomplete,
  message? : String = "",
) -> Result[CommandExecution, ModbusError] {
  if command_id == "" || started_at < 0 || finished_at < started_at {
    return Err(InvalidData)
  }
  let selected_response = if response.unit_id == 0 {
    None
  } else {
    Some(response)
  }
  let selected_error = if state == Acknowledged { None } else { Some(error) }
  Ok({
    command_id,
    state,
    started_at,
    finished_at,
    response: selected_response,
    error: selected_error,
    message,
  })
}

///|
pub fn CommandExecution::command_id(self : CommandExecution) -> String {
  self.command_id
}

///|
pub fn CommandExecution::state(self : CommandExecution) -> DeviceCommandState {
  self.state
}

///|
pub fn CommandExecution::started_at(self : CommandExecution) -> Int {
  self.started_at
}

///|
pub fn CommandExecution::finished_at(self : CommandExecution) -> Int {
  self.finished_at
}

///|
pub fn CommandExecution::duration(self : CommandExecution) -> Int {
  self.finished_at - self.started_at
}

///|
pub fn CommandExecution::response(self : CommandExecution) -> Frame? {
  self.response
}

///|
pub fn CommandExecution::error(self : CommandExecution) -> ModbusError? {
  self.error
}

///|
pub fn CommandExecution::message(self : CommandExecution) -> String {
  self.message
}

///|
/// Immutable audit event for compliance exports.
pub(all) struct CommandAuditEntry {
  sequence : Int
  command_id : String
  principal : String
  device_id : String
  operation : String
  state : DeviceCommandState
  timestamp : Int
  detail : String
}

///|
pub fn CommandAuditEntry::new(
  sequence : Int,
  command : DeviceCommand,
  state : DeviceCommandState,
  timestamp : Int,
  detail? : String = "",
) -> Result[CommandAuditEntry, ModbusError] {
  if sequence < 1 || timestamp < 0 {
    return Err(InvalidData)
  }
  Ok({
    sequence,
    command_id: command.id(),
    principal: command.principal(),
    device_id: command.device_id(),
    operation: device_command_kind_name(command.kind()),
    state,
    timestamp,
    detail,
  })
}

///|
pub fn CommandAuditEntry::sequence(self : CommandAuditEntry) -> Int {
  self.sequence
}

///|
pub fn CommandAuditEntry::command_id(self : CommandAuditEntry) -> String {
  self.command_id
}

///|
pub fn CommandAuditEntry::principal(self : CommandAuditEntry) -> String {
  self.principal
}

///|
pub fn CommandAuditEntry::device_id(self : CommandAuditEntry) -> String {
  self.device_id
}

///|
pub fn CommandAuditEntry::operation(self : CommandAuditEntry) -> String {
  self.operation
}

///|
pub fn CommandAuditEntry::state(self : CommandAuditEntry) -> DeviceCommandState {
  self.state
}

///|
pub fn CommandAuditEntry::timestamp(self : CommandAuditEntry) -> Int {
  self.timestamp
}

///|
pub fn CommandAuditEntry::detail(self : CommandAuditEntry) -> String {
  self.detail
}

///|
/// Central queue and audit log used by a control-plane service.
pub(all) struct CommandCenter {
  queue : Array[DeviceCommand]
  completed : Array[CommandExecution]
  audit : Array[CommandAuditEntry]
  max_queue : Int
  max_audit : Int
  mut sequence : Int
}

///|
pub fn CommandCenter::new(
  max_queue? : Int = 1024,
  max_audit? : Int = 8192,
) -> Result[CommandCenter, ModbusError] {
  if max_queue < 1 || max_audit < 1 {
    Err(InvalidData)
  } else {
    Ok({
      queue: [],
      completed: [],
      audit: [],
      max_queue,
      max_audit,
      sequence: 0,
    })
  }
}

///|
pub fn CommandCenter::queue_count(self : CommandCenter) -> Int {
  self.queue.length()
}

///|
pub fn CommandCenter::completed_count(self : CommandCenter) -> Int {
  self.completed.length()
}

///|
pub fn CommandCenter::audit_count(self : CommandCenter) -> Int {
  self.audit.length()
}

///|
pub fn CommandCenter::submit(
  self : CommandCenter,
  command : DeviceCommand,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 || self.queue.length() >= self.max_queue {
    return Err(CapacityExceeded)
  }
  match command.set_state(Validating) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match command.request() {
    Err(error) => {
      ignore(command.set_state(Rejected))
      return Err(error)
    }
    Ok(_) => ()
  }
  ignore(command.set_state(Queued))
  self.queue.push(command)
  self.record_audit(command, Queued, timestamp, "admitted")
  Ok(())
}

///|
pub fn CommandCenter::next(
  self : CommandCenter,
  timestamp : Int,
) -> Result[DeviceCommand, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  if self.queue.length() == 0 {
    return Err(Incomplete)
  }
  let best = command_best_index(self.queue)
  let command = self.queue.remove(best)
  ignore(command.set_state(Dispatched))
  self.record_audit(command, Dispatched, timestamp, "dispatched")
  Ok(command)
}

///|
fn command_best_index(queue : Array[DeviceCommand]) -> Int {
  let mut best = 0
  for i in 1..<queue.length() {
    if command_priority(queue[i].kind()) > command_priority(queue[best].kind()) {
      best = i
    }
  }
  best
}

///|
fn command_priority(kind : DeviceCommandKind) -> Int {
  match kind {
    RestartDeviceCommand | ClearAlarmCommand => 4
    WriteCoilCommand
    | WriteRegisterCommand
    | WriteCoilsCommand
    | WriteRegistersCommand => 3
    ReadVerificationCommand => 2
    CustomCommand => 1
  }
}

///|
/// Complete a dispatched command and retain its result for inspection.
pub fn CommandCenter::finish(
  self : CommandCenter,
  command : DeviceCommand,
  execution : CommandExecution,
) -> Result[Unit, ModbusError] {
  if execution.command_id() != command.id() {
    return Err(UnitMismatch)
  }
  self.completed.push(execution)
  self.record_audit(
    command,
    execution.state(),
    execution.finished_at(),
    execution.message(),
  )
  Ok(())
}

///|
pub fn CommandCenter::cancel(
  self : CommandCenter,
  command_id : String,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if command_id == "" || timestamp < 0 {
    return Err(InvalidData)
  }
  for i in 0..<self.queue.length() {
    if self.queue[i].id() == command_id {
      let command = self.queue.remove(i)
      ignore(command.set_state(CancelledCommand))
      self.record_audit(
        command,
        CancelledCommand,
        timestamp,
        "cancelled-before-dispatch",
      )
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
fn CommandCenter::record_audit(
  self : CommandCenter,
  command : DeviceCommand,
  state : DeviceCommandState,
  timestamp : Int,
  detail : String,
) -> Unit {
  if self.audit.length() >= self.max_audit {
    ignore(self.audit.remove(0))
  }
  self.sequence += 1
  match
    CommandAuditEntry::new(self.sequence, command, state, timestamp, detail~) {
    Ok(entry) => self.audit.push(entry)
    Err(_) => ()
  }
}

///|
pub fn CommandCenter::find_audit(
  self : CommandCenter,
  command_id : String,
) -> Array[CommandAuditEntry] {
  let result : Array[CommandAuditEntry] = []
  for entry in self.audit {
    if entry.command_id() == command_id {
      result.push(entry)
    }
  }
  result
}

///|
pub fn CommandCenter::recent(
  self : CommandCenter,
  limit : Int,
) -> Result[Array[CommandAuditEntry], ModbusError] {
  if limit < 1 {
    return Err(InvalidQuantity)
  }
  let result : Array[CommandAuditEntry] = []
  let start = if self.audit.length() > limit {
    self.audit.length() - limit
  } else {
    0
  }
  for i in start..<self.audit.length() {
    result.push(self.audit[i])
  }
  Ok(result)
}

///|
pub fn CommandCenter::state_counts(self : CommandCenter) -> Array[Int] {
  let counts : Array[Int] = [0, 0, 0, 0, 0, 0, 0, 0]
  for entry in self.audit {
    let index = match entry.state() {
      Queued => 0
      Validating => 1
      Dispatched => 2
      Acknowledged => 3
      Rejected => 4
      TimedOut => 5
      FailedCommand => 6
      CancelledCommand => 7
    }
    counts[index] += 1
  }
  counts
}
