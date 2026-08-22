///|
/// Category assigned to a diagnostic finding.
pub(all) enum DiagnosticCategory {
  Framing
  Addressing
  FunctionSupport
  Payload
  Timing
  Capacity
  Configuration
  Interoperability
} derive(Debug, Eq)

///|
/// Severity of a diagnostic finding.
pub(all) enum DiagnosticSeverity {
  Note
  WarningFinding
  ErrorFinding
} derive(Debug, Eq)

///|
pub fn diagnostic_category_name(value : DiagnosticCategory) -> String {
  match value {
    Framing => "framing"
    Addressing => "addressing"
    FunctionSupport => "function-support"
    Payload => "payload"
    Timing => "timing"
    Capacity => "capacity"
    Configuration => "configuration"
    Interoperability => "interoperability"
  }
}

///|
pub fn diagnostic_severity_name(value : DiagnosticSeverity) -> String {
  match value {
    Note => "note"
    WarningFinding => "warning"
    ErrorFinding => "error"
  }
}

///|
/// One actionable finding from a diagnostic pass.
pub(all) struct DiagnosticIssue {
  code : String
  category : DiagnosticCategory
  severity : DiagnosticSeverity
  message : String
  context : String
  suggestion : String
}

///|
pub fn DiagnosticIssue::new(
  code : String,
  category : DiagnosticCategory,
  severity : DiagnosticSeverity,
  message : String,
  context? : String = "",
  suggestion? : String = "",
) -> Result[DiagnosticIssue, ModbusError] {
  if code == "" || message == "" {
    Err(InvalidData)
  } else {
    Ok({ code, category, severity, message, context, suggestion })
  }
}

///|
pub fn DiagnosticIssue::code(self : DiagnosticIssue) -> String {
  self.code
}

///|
pub fn DiagnosticIssue::category(self : DiagnosticIssue) -> DiagnosticCategory {
  self.category
}

///|
pub fn DiagnosticIssue::severity(self : DiagnosticIssue) -> DiagnosticSeverity {
  self.severity
}

///|
pub fn DiagnosticIssue::message(self : DiagnosticIssue) -> String {
  self.message
}

///|
pub fn DiagnosticIssue::context(self : DiagnosticIssue) -> String {
  self.context
}

///|
pub fn DiagnosticIssue::suggestion(self : DiagnosticIssue) -> String {
  self.suggestion
}

///|
pub fn DiagnosticIssue::summary(self : DiagnosticIssue) -> String {
  self.code + " " + diagnostic_severity_name(self.severity) + " " + self.message
}

///|
/// A report collected from one or more protocol checks.
pub(all) struct DiagnosticReport {
  name : String
  issues : Array[DiagnosticIssue]
  max_issues : Int
  mut inspected : Int
}

///|
pub fn DiagnosticReport::new(
  name? : String = "protocol-diagnostics",
  max_issues? : Int = 1024,
) -> Result[DiagnosticReport, ModbusError] {
  if name == "" || max_issues < 1 {
    Err(InvalidData)
  } else {
    Ok({ name, issues: [], max_issues, inspected: 0 })
  }
}

///|
pub fn DiagnosticReport::name(self : DiagnosticReport) -> String {
  self.name
}

///|
pub fn DiagnosticReport::inspected(self : DiagnosticReport) -> Int {
  self.inspected
}

///|
pub fn DiagnosticReport::add(
  self : DiagnosticReport,
  issue : DiagnosticIssue,
) -> Result[Unit, ModbusError] {
  if self.issues.length() >= self.max_issues {
    Err(CapacityExceeded)
  } else {
    self.issues.push(issue)
    Ok(())
  }
}

///|
pub fn DiagnosticReport::inspect_one(
  self : DiagnosticReport,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  self.inspected += 1
  match validate_wire_frame(frame, true) {
    Ok(_) => ()
    Err(error) => {
      let issue = DiagnosticIssue::new(
        "FRAME-" + error_name(error),
        Framing,
        ErrorFinding,
        "wire frame validation failed: " + error_name(error),
        context=format_frame(frame),
        suggestion="check unit id, function code and PDU length",
      )
      match issue {
        Ok(value) => ignore(self.add(value))
        Err(value) => return Err(value)
      }
    }
  }
  if frame.unit_id == 0 &&
    frame.pdu.function != 5 &&
    frame.pdu.function != 6 &&
    frame.pdu.function != 15 &&
    frame.pdu.function != 16 {
    let issue = DiagnosticIssue::new(
      "BROADCAST-READ",
      Addressing,
      WarningFinding,
      "broadcast is only valid for write requests",
      context=format_frame(frame),
      suggestion="use a unit id from 1 through 247 for reads",
    ).unwrap()
    ignore(self.add(issue))
  }
  match validate_pdu(frame.pdu) {
    Ok(_) => ()
    Err(error) => {
      let issue = DiagnosticIssue::new(
        "PDU-" + error_name(error),
        Payload,
        ErrorFinding,
        "PDU shape is not valid for its function code",
        context=function_name(frame.pdu.function),
        suggestion="construct the request with a checked function builder",
      ).unwrap()
      ignore(self.add(issue))
    }
  }
  Ok(())
}

///|
pub fn DiagnosticReport::inspect_wire(
  self : DiagnosticReport,
  mode : Mode,
  bytes : Array[Byte],
) -> Unit {
  self.inspected += 1
  match decode_transaction(mode, bytes) {
    Ok(_) => ()
    Err(error) => {
      let category = match error {
        InvalidChecksum | InvalidAscii | InvalidMbap => Framing
        Incomplete => Capacity
        _ => Payload
      }
      let issue = DiagnosticIssue::new(
        "WIRE-" + error_name(error),
        category,
        ErrorFinding,
        "wire bytes could not be decoded",
        context=mode_name(mode),
        suggestion="capture a complete ADU and verify the checksum",
      ).unwrap()
      ignore(self.add(issue))
    }
  }
}

///|
pub fn DiagnosticReport::issues(
  self : DiagnosticReport,
) -> Array[DiagnosticIssue] {
  let result : Array[DiagnosticIssue] = []
  for issue in self.issues {
    result.push(issue)
  }
  result
}

///|
pub fn DiagnosticReport::length(self : DiagnosticReport) -> Int {
  self.issues.length()
}

///|
pub fn DiagnosticReport::count_severity(
  self : DiagnosticReport,
  severity : DiagnosticSeverity,
) -> Int {
  let mut count = 0
  for issue in self.issues {
    if issue.severity() == severity {
      count += 1
    }
  }
  count
}

///|
pub fn DiagnosticReport::count_category(
  self : DiagnosticReport,
  category : DiagnosticCategory,
) -> Int {
  let mut count = 0
  for issue in self.issues {
    if issue.category() == category {
      count += 1
    }
  }
  count
}

///|
pub fn DiagnosticReport::has_errors(self : DiagnosticReport) -> Bool {
  self.count_severity(ErrorFinding) > 0
}

///|
pub fn DiagnosticReport::has_warnings(self : DiagnosticReport) -> Bool {
  self.count_severity(WarningFinding) > 0
}

///|
pub fn DiagnosticReport::ok(self : DiagnosticReport) -> Bool {
  !self.has_errors()
}

///|
pub fn DiagnosticReport::clear(self : DiagnosticReport) -> Unit {
  self.issues.clear()
  self.inspected = 0
}

///|
pub fn DiagnosticReport::summary(self : DiagnosticReport) -> String {
  self.name +
  " inspected=" +
  self.inspected.to_string() +
  " issues=" +
  self.length().to_string() +
  " errors=" +
  self.count_severity(ErrorFinding).to_string() +
  " warnings=" +
  self.count_severity(WarningFinding).to_string()
}

///|
/// A set of capabilities expected from a server or gateway.
pub(all) struct CapabilitySet {
  functions : Array[Byte]
  modes : Array[Mode]
  max_pdu : Int
  broadcasts : Bool
}

///|
pub fn CapabilitySet::new(
  max_pdu? : Int = 253,
  broadcasts? : Bool = true,
) -> Result[CapabilitySet, ModbusError] {
  if max_pdu < 1 || max_pdu > 253 {
    Err(InvalidLength)
  } else {
    Ok({ functions: [], modes: [], max_pdu, broadcasts })
  }
}

///|
pub fn CapabilitySet::add_function(
  self : CapabilitySet,
  function : Byte,
) -> Result[Unit, ModbusError] {
  if !supported_function(function) {
    return Err(Unsupported)
  }
  for current in self.functions {
    if current == function {
      return Ok(())
    }
  }
  self.functions.push(function)
  Ok(())
}

///|
pub fn CapabilitySet::add_mode(self : CapabilitySet, mode : Mode) -> Unit {
  for current in self.modes {
    if current == mode {
      return
    }
  }
  self.modes.push(mode)
}

///|
pub fn CapabilitySet::supports_function(
  self : CapabilitySet,
  function : Byte,
) -> Bool {
  for current in self.functions {
    if current == function {
      return true
    }
  }
  false
}

///|
pub fn CapabilitySet::supports_mode(self : CapabilitySet, mode : Mode) -> Bool {
  for current in self.modes {
    if current == mode {
      return true
    }
  }
  false
}

///|
pub fn CapabilitySet::functions(self : CapabilitySet) -> Array[Byte] {
  let result : Array[Byte] = []
  for value in self.functions {
    result.push(value)
  }
  result
}

///|
pub fn CapabilitySet::modes(self : CapabilitySet) -> Array[Mode] {
  let result : Array[Mode] = []
  for value in self.modes {
    result.push(value)
  }
  result
}

///|
pub fn CapabilitySet::max_pdu(self : CapabilitySet) -> Int {
  self.max_pdu
}

///|
pub fn CapabilitySet::broadcasts(self : CapabilitySet) -> Bool {
  self.broadcasts
}

///|
pub fn CapabilitySet::validate_frame(
  self : CapabilitySet,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  if frame.pdu.data.length() > self.max_pdu {
    return Err(InvalidLength)
  }
  if !self.supports_function(ordinary_function(frame.pdu.function)) {
    return Err(Unsupported)
  }
  if frame.unit_id == 0 && !self.broadcasts {
    return Err(InvalidUnitId)
  }
  Ok(())
}

///|
pub fn CapabilitySet::coverage(
  self : CapabilitySet,
  expected : Array[Byte],
) -> Int {
  if expected.length() == 0 {
    return 100
  }
  let mut found = 0
  for function in expected {
    if self.supports_function(function) {
      found += 1
    }
  }
  found * 100 / expected.length()
}

///|
pub fn default_server_capabilities() -> CapabilitySet {
  let result = CapabilitySet::new().unwrap()
  let functions : Array[Byte] = [
    1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 15, 16, 17, 20, 21, 22, 23, 24, 43,
  ]
  for function in functions {
    ignore(result.add_function(function))
  }
  result.add_mode(Rtu)
  result.add_mode(Ascii)
  result.add_mode(Tcp)
  result
}

///|
pub fn diagnose_frames(frames : Array[Frame]) -> DiagnosticReport {
  let report = DiagnosticReport::new().unwrap()
  for frame in frames {
    ignore(report.inspect_one(frame))
  }
  report
}

///|
pub fn diagnose_capability_gap(
  capabilities : CapabilitySet,
  expected_functions : Array[Byte],
) -> DiagnosticReport {
  let report = DiagnosticReport::new(name="capability-gap").unwrap()
  for function in expected_functions {
    if !capabilities.supports_function(function) {
      let issue = DiagnosticIssue::new(
        "FUNC-" + function.to_string(),
        FunctionSupport,
        ErrorFinding,
        "required function is not supported",
        context=function_name(function),
        suggestion="add a handler or remove the function from the deployment profile",
      ).unwrap()
      ignore(report.add(issue))
    }
  }
  report
}
