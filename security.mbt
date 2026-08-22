///|
/// High-level operation guarded by an access policy.
pub(all) enum AccessOperation {
  ReadOperation
  WriteOperation
  DiagnosticsOperation
  IdentificationOperation
} derive(Debug, Eq)

///|
/// Role used by a deployment policy.
pub(all) enum AccessRole {
  Observer
  Operator
  Engineer
  Administrator
} derive(Debug, Eq)

///|
pub fn access_operation_name(value : AccessOperation) -> String {
  match value {
    ReadOperation => "read"
    WriteOperation => "write"
    DiagnosticsOperation => "diagnostics"
    IdentificationOperation => "identification"
  }
}

///|
pub fn access_role_rank(value : AccessRole) -> Int {
  match value {
    Observer => 0
    Operator => 1
    Engineer => 2
    Administrator => 3
  }
}

///|
/// A rule matching unit ids and function codes.
pub(all) struct AccessRule {
  name : String
  role : AccessRole
  operation : AccessOperation
  unit_start : Byte
  unit_end : Byte
  functions : Array[Byte]
  mut enabled : Bool
}

///|
pub fn AccessRule::new(
  name : String,
  role : AccessRole,
  operation : AccessOperation,
  unit_start : Byte,
  unit_end : Byte,
  functions : Array[Byte],
) -> Result[AccessRule, ModbusError] {
  if name == "" ||
    unit_start > unit_end ||
    !is_valid_unit_id(unit_start, broadcast=false) ||
    !is_valid_unit_id(unit_end, broadcast=false) ||
    functions.length() == 0 {
    return Err(InvalidData)
  }
  for function in functions {
    if !supported_function(function) {
      return Err(Unsupported)
    }
  }
  Ok({
    name,
    role,
    operation,
    unit_start,
    unit_end,
    functions: copy_bytes(functions),
    enabled: true,
  })
}

///|
pub fn AccessRule::name(self : AccessRule) -> String {
  self.name
}

///|
pub fn AccessRule::role(self : AccessRule) -> AccessRole {
  self.role
}

///|
pub fn AccessRule::operation(self : AccessRule) -> AccessOperation {
  self.operation
}

///|
pub fn AccessRule::enabled(self : AccessRule) -> Bool {
  self.enabled
}

///|
pub fn AccessRule::set_enabled(self : AccessRule, value : Bool) -> Unit {
  self.enabled = value
}

///|
pub fn AccessRule::matches(
  self : AccessRule,
  role : AccessRole,
  operation : AccessOperation,
  frame : Frame,
) -> Bool {
  if !self.enabled ||
    access_role_rank(role) < access_role_rank(self.role) ||
    operation != self.operation {
    return false
  }
  if frame.unit_id < self.unit_start || frame.unit_id > self.unit_end {
    return false
  }
  let ordinary = ordinary_function(frame.pdu.function)
  for function in self.functions {
    if function == ordinary {
      return true
    }
  }
  false
}

///|
pub fn AccessRule::summary(self : AccessRule) -> String {
  self.name +
  " role=" +
  access_role_rank(self.role).to_string() +
  " operation=" +
  access_operation_name(self.operation)
}

///|
/// A first-match access policy with an explicit default decision.
pub(all) struct AccessPolicy {
  rules : Array[AccessRule]
  max_rules : Int
  mut default_allow : Bool
}

///|
pub fn AccessPolicy::new(
  default_allow? : Bool = false,
  max_rules? : Int = 256,
) -> Result[AccessPolicy, ModbusError] {
  if max_rules < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ rules: [], max_rules, default_allow })
  }
}

///|
pub fn AccessPolicy::add(
  self : AccessPolicy,
  rule : AccessRule,
) -> Result[Unit, ModbusError] {
  if self.rules.length() >= self.max_rules {
    Err(CapacityExceeded)
  } else {
    self.rules.push(rule)
    Ok(())
  }
}

///|
pub fn AccessPolicy::remove(
  self : AccessPolicy,
  name : String,
) -> Result[AccessRule, ModbusError] {
  for index, rule in self.rules {
    if rule.name() == name {
      ignore(self.rules.remove(index))
      return Ok(rule)
    }
  }
  Err(InvalidData)
}

///|
pub fn AccessPolicy::length(self : AccessPolicy) -> Int {
  self.rules.length()
}

///|
pub fn AccessPolicy::allows(
  self : AccessPolicy,
  role : AccessRole,
  operation : AccessOperation,
  frame : Frame,
) -> Bool {
  for rule in self.rules {
    if rule.matches(role, operation, frame) {
      return true
    }
  }
  self.default_allow
}

///|
pub fn AccessPolicy::decision(
  self : AccessPolicy,
  role : AccessRole,
  operation : AccessOperation,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  if self.allows(role, operation, frame) {
    Ok(())
  } else {
    Err(Unsupported)
  }
}

///|
pub fn AccessPolicy::rules(self : AccessPolicy) -> Array[AccessRule] {
  let result : Array[AccessRule] = []
  for rule in self.rules {
    result.push(rule)
  }
  result
}

///|
pub fn AccessPolicy::set_default(self : AccessPolicy, allow : Bool) -> Unit {
  self.default_allow = allow
}

///|
pub fn AccessPolicy::summary(self : AccessPolicy) -> String {
  "rules=" +
  self.rules.length().to_string() +
  " default=" +
  (if self.default_allow { "allow" } else { "deny" })
}

///|
/// A fixed-size request window for rate limiting a transport or unit.
pub(all) struct RateWindow {
  width : Int
  limit : Int
  timestamps : Array[Int]
}

///|
pub fn RateWindow::new(
  width : Int,
  limit : Int,
) -> Result[RateWindow, ModbusError] {
  if width < 1 || limit < 1 {
    Err(InvalidData)
  } else {
    Ok({ width, limit, timestamps: [] })
  }
}

///|
pub fn RateWindow::width(self : RateWindow) -> Int {
  self.width
}

///|
pub fn RateWindow::limit(self : RateWindow) -> Int {
  self.limit
}

///|
pub fn RateWindow::prune(self : RateWindow, now : Int) -> Unit {
  while self.timestamps.length() > 0 && now - self.timestamps[0] >= self.width {
    ignore(self.timestamps.remove(0))
  }
}

///|
pub fn RateWindow::allow(self : RateWindow, now : Int) -> Bool {
  if now < 0 {
    return false
  }
  self.prune(now)
  if self.timestamps.length() >= self.limit {
    false
  } else {
    self.timestamps.push(now)
    true
  }
}

///|
pub fn RateWindow::remaining(self : RateWindow, now : Int) -> Int {
  self.prune(now)
  self.limit - self.timestamps.length()
}

///|
pub fn RateWindow::reset(self : RateWindow) -> Unit {
  self.timestamps.clear()
}

///|
pub fn RateWindow::count(self : RateWindow, now : Int) -> Int {
  self.prune(now)
  self.timestamps.length()
}

///|
/// A token bucket with integer tokens, suitable for frame-level quotas.
pub(all) struct TokenBucket {
  capacity : Int
  refill_interval : Int
  mut tokens : Int
  mut last_refill : Int
}

///|
pub fn TokenBucket::new(
  capacity : Int,
  refill_interval : Int,
  now : Int,
) -> Result[TokenBucket, ModbusError] {
  if capacity < 1 || refill_interval < 1 || now < 0 {
    Err(InvalidData)
  } else {
    Ok({ capacity, refill_interval, tokens: capacity, last_refill: now })
  }
}

///|
pub fn TokenBucket::capacity(self : TokenBucket) -> Int {
  self.capacity
}

///|
pub fn TokenBucket::tokens(self : TokenBucket, now : Int) -> Int {
  self.refill(now)
  self.tokens
}

///|
pub fn TokenBucket::refill(self : TokenBucket, now : Int) -> Unit {
  if now <= self.last_refill {
    return
  }
  let added = (now - self.last_refill) / self.refill_interval
  if added > 0 {
    self.tokens = if self.tokens + added > self.capacity {
      self.capacity
    } else {
      self.tokens + added
    }
    self.last_refill += added * self.refill_interval
  }
}

///|
pub fn TokenBucket::take(self : TokenBucket, amount : Int, now : Int) -> Bool {
  if amount < 1 {
    return false
  }
  self.refill(now)
  if self.tokens < amount {
    false
  } else {
    self.tokens -= amount
    true
  }
}

///|
pub fn TokenBucket::reset(
  self : TokenBucket,
  now : Int,
) -> Result[Unit, ModbusError] {
  if now < 0 {
    Err(InvalidData)
  } else {
    self.tokens = self.capacity
    self.last_refill = now
    Ok(())
  }
}

///|
/// Security audit record generated by a policy decision.
pub(all) struct SecurityAudit {
  sequence : Int
  timestamp : Int
  principal : String
  role : AccessRole
  operation : AccessOperation
  unit_id : Byte
  function : Byte
  allowed : Bool
  reason : String
}

///|
pub fn SecurityAudit::new(
  sequence : Int,
  timestamp : Int,
  principal : String,
  role : AccessRole,
  operation : AccessOperation,
  frame : Frame,
  allowed : Bool,
  reason : String,
) -> Result[SecurityAudit, ModbusError] {
  if sequence < 1 || timestamp < 0 || principal == "" || reason == "" {
    Err(InvalidData)
  } else {
    Ok({
      sequence,
      timestamp,
      principal,
      role,
      operation,
      unit_id: frame.unit_id,
      function: frame.pdu.function,
      allowed,
      reason,
    })
  }
}

///|
pub fn SecurityAudit::allowed(self : SecurityAudit) -> Bool {
  self.allowed
}

///|
pub fn SecurityAudit::sequence(self : SecurityAudit) -> Int {
  self.sequence
}

///|
pub fn SecurityAudit::summary(self : SecurityAudit) -> String {
  self.principal +
  " " +
  access_operation_name(self.operation) +
  " unit=" +
  self.unit_id.to_string() +
  " function=" +
  self.function.to_string() +
  " allowed=" +
  (if self.allowed { "true" } else { "false" })
}

///|
pub fn evaluate_access(
  policy : AccessPolicy,
  role : AccessRole,
  operation : AccessOperation,
  principal : String,
  frame : Frame,
  timestamp : Int,
  sequence : Int,
) -> Result[SecurityAudit, ModbusError] {
  let allowed = policy.allows(role, operation, frame)
  SecurityAudit::new(
    sequence,
    timestamp,
    principal,
    role,
    operation,
    frame,
    allowed,
    if allowed {
      "policy-allow"
    } else {
      "policy-deny"
    },
  )
}
