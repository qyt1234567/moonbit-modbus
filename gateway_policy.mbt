///|
/// Action taken when a frame matches a gateway policy rule.
pub(all) enum BridgeAction {
  ForwardBridge
  RewriteBridge
  DenyBridge
  AuditBridge
  RateLimitBridge
} derive(Debug, Eq)

///|
/// Rule matching a source request and selecting a target route.
pub(all) struct ServiceBridgeRule {
  id : String
  source_unit : Byte
  target_unit : Byte
  function : Byte
  source_start : UInt16
  span : Int
  target_start : UInt16
  action : BridgeAction
  priority : Int
  mut enabled : Bool
  tag : String
}

///|
pub fn ServiceBridgeRule::new(
  id : String,
  source_unit : Byte,
  target_unit : Byte,
  function : Byte,
  source_start : UInt16,
  span : Int,
  target_start : UInt16,
  action : BridgeAction,
  priority? : Int = 0,
  tag? : String = "",
) -> Result[ServiceBridgeRule, ModbusError] {
  if id == "" ||
    !is_valid_unit_id(source_unit) ||
    !is_valid_unit_id(target_unit) ||
    function == 0 ||
    span < 1 ||
    priority < 0 {
    return Err(InvalidData)
  }
  if !valid_address_range(source_start, span) ||
    !valid_address_range(target_start, span) {
    return Err(InvalidAddress)
  }
  Ok({
    id,
    source_unit,
    target_unit,
    function,
    source_start,
    span,
    target_start,
    action,
    priority,
    enabled: true,
    tag,
  })
}

///|
pub fn ServiceBridgeRule::id(self : ServiceBridgeRule) -> String {
  self.id
}

///|
pub fn ServiceBridgeRule::source_unit(self : ServiceBridgeRule) -> Byte {
  self.source_unit
}

///|
pub fn ServiceBridgeRule::target_unit(self : ServiceBridgeRule) -> Byte {
  self.target_unit
}

///|
pub fn ServiceBridgeRule::function(self : ServiceBridgeRule) -> Byte {
  self.function
}

///|
pub fn ServiceBridgeRule::source_start(self : ServiceBridgeRule) -> UInt16 {
  self.source_start
}

///|
pub fn ServiceBridgeRule::target_start(self : ServiceBridgeRule) -> UInt16 {
  self.target_start
}

///|
pub fn ServiceBridgeRule::span(self : ServiceBridgeRule) -> Int {
  self.span
}

///|
pub fn ServiceBridgeRule::action(self : ServiceBridgeRule) -> BridgeAction {
  self.action
}

///|
pub fn ServiceBridgeRule::priority(self : ServiceBridgeRule) -> Int {
  self.priority
}

///|
pub fn ServiceBridgeRule::enabled(self : ServiceBridgeRule) -> Bool {
  self.enabled
}

///|
pub fn ServiceBridgeRule::tag(self : ServiceBridgeRule) -> String {
  self.tag
}

///|
pub fn ServiceBridgeRule::set_enabled(
  self : ServiceBridgeRule,
  enabled : Bool,
) -> Unit {
  self.enabled = enabled
}

///|
pub fn ServiceBridgeRule::matches(
  self : ServiceBridgeRule,
  frame : Frame,
) -> Bool {
  self.enabled &&
  frame.unit_id == self.source_unit &&
  frame.pdu.function == self.function &&
  frame.pdu.data.length() >= 2 &&
  frame.pdu.data[0].to_int() * 256 + frame.pdu.data[1].to_int() >=
  self.source_start.to_int() &&
  frame.pdu.data[0].to_int() * 256 + frame.pdu.data[1].to_int() <
  self.source_start.to_int() + self.span
}

///|
pub fn ServiceBridgeRule::rewrite(
  self : ServiceBridgeRule,
  frame : Frame,
) -> Result[Frame, ModbusError] {
  if !self.matches(frame) {
    return Err(UnitMismatch)
  }
  if frame.pdu.data.length() < 2 {
    return Err(InvalidLength)
  }
  let address = frame.pdu.data[0].to_int() * 256 + frame.pdu.data[1].to_int()
  let translated = self.target_start.to_int() +
    address -
    self.source_start.to_int()
  let data = frame.pdu.data.copy()
  data[0] = (translated / 256).to_byte()
  data[1] = translated.to_byte()
  Ok(Frame::new(self.target_unit, frame.pdu.function, data))
}

///|
pub fn bridge_action_name(action : BridgeAction) -> String {
  match action {
    ForwardBridge => "forward"
    RewriteBridge => "rewrite"
    DenyBridge => "deny"
    AuditBridge => "audit"
    RateLimitBridge => "rate-limit"
  }
}

///|
/// Result of applying one gateway rule to a frame.
pub(all) struct BridgeDecision {
  rule_id : String?
  action : BridgeAction
  frame : Frame?
  reason : String
  matched : Bool
}

///|
pub fn BridgeDecision::new(
  action : BridgeAction,
  reason : String,
) -> BridgeDecision {
  { rule_id: None, action, frame: None, reason, matched: false }
}

///|
pub fn BridgeDecision::matched(
  rule : ServiceBridgeRule,
  action : BridgeAction,
  frame : Frame?,
  reason : String,
) -> BridgeDecision {
  { rule_id: Some(rule.id()), action, frame, reason, matched: true }
}

///|
pub fn BridgeDecision::rule_id(self : BridgeDecision) -> String? {
  self.rule_id
}

///|
pub fn BridgeDecision::action(self : BridgeDecision) -> BridgeAction {
  self.action
}

///|
pub fn BridgeDecision::frame(self : BridgeDecision) -> Frame? {
  self.frame
}

///|
pub fn BridgeDecision::reason(self : BridgeDecision) -> String {
  self.reason
}

///|
pub fn BridgeDecision::matched_rule(self : BridgeDecision) -> Bool {
  self.matched
}

///|
/// An ordered policy set for one gateway route.
pub(all) struct ServiceGatewayPolicy {
  id : String
  source : String
  destination : String
  rules : Array[ServiceBridgeRule]
  default_action : BridgeAction
  max_rules : Int
  mut revision : Int
}

///|
pub fn ServiceGatewayPolicy::new(
  id : String,
  source : String,
  destination : String,
  default_action? : BridgeAction = DenyBridge,
  max_rules? : Int = 256,
) -> Result[ServiceGatewayPolicy, ModbusError] {
  if id == "" ||
    source == "" ||
    destination == "" ||
    source == destination ||
    max_rules < 1 {
    return Err(InvalidData)
  }
  Ok({
    id,
    source,
    destination,
    rules: [],
    default_action,
    max_rules,
    revision: 0,
  })
}

///|
pub fn ServiceGatewayPolicy::id(self : ServiceGatewayPolicy) -> String {
  self.id
}

///|
pub fn ServiceGatewayPolicy::source(self : ServiceGatewayPolicy) -> String {
  self.source
}

///|
pub fn ServiceGatewayPolicy::destination(self : ServiceGatewayPolicy) -> String {
  self.destination
}

///|
pub fn ServiceGatewayPolicy::rule_count(self : ServiceGatewayPolicy) -> Int {
  self.rules.length()
}

///|
pub fn ServiceGatewayPolicy::revision(self : ServiceGatewayPolicy) -> Int {
  self.revision
}

///|
pub fn ServiceGatewayPolicy::default_action(
  self : ServiceGatewayPolicy,
) -> BridgeAction {
  self.default_action
}

///|
pub fn ServiceGatewayPolicy::add_rule(
  self : ServiceGatewayPolicy,
  rule : ServiceBridgeRule,
) -> Result[Unit, ModbusError] {
  if self.rules.length() >= self.max_rules {
    return Err(CapacityExceeded)
  }
  for existing in self.rules {
    if existing.id() == rule.id() {
      return Err(InvalidData)
    }
  }
  self.rules.push(rule)
  self.revision += 1
  Ok(())
}

///|
pub fn ServiceGatewayPolicy::remove_rule(
  self : ServiceGatewayPolicy,
  id : String,
) -> Result[ServiceBridgeRule, ModbusError] {
  for i in 0..<self.rules.length() {
    if self.rules[i].id() == id {
      self.revision += 1
      return Ok(self.rules.remove(i))
    }
  }
  Err(InvalidData)
}

///|
pub fn ServiceGatewayPolicy::rule(
  self : ServiceGatewayPolicy,
  id : String,
) -> ServiceBridgeRule? {
  for rule in self.rules {
    if rule.id() == id {
      return Some(rule)
    }
  }
  None
}

///|
/// Find the highest priority matching rule and execute its action.
pub fn ServiceGatewayPolicy::evaluate(
  self : ServiceGatewayPolicy,
  frame : Frame,
) -> Result[BridgeDecision, ModbusError] {
  let mut selected : ServiceBridgeRule? = None
  for rule in self.rules {
    if rule.matches(frame) {
      match selected {
        None => selected = Some(rule)
        Some(previous) =>
          if rule.priority() > previous.priority() {
            selected = Some(rule)
          }
      }
    }
  }
  match selected {
    None => Ok(BridgeDecision::new(self.default_action, "no-match"))
    Some(rule) =>
      match rule.action() {
        ForwardBridge | AuditBridge =>
          Ok(
            BridgeDecision::matched(rule, rule.action(), Some(frame), "matched"),
          )
        RewriteBridge => {
          let rewritten = match rule.rewrite(frame) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          Ok(
            BridgeDecision::matched(
              rule,
              RewriteBridge,
              Some(rewritten),
              "rewritten",
            ),
          )
        }
        DenyBridge =>
          Ok(BridgeDecision::matched(rule, DenyBridge, None, "denied"))
        RateLimitBridge =>
          Ok(
            BridgeDecision::matched(rule, RateLimitBridge, None, "rate-limited"),
          )
      }
  }
}

///|
/// Validate rule ordering and overlapping address windows.
pub fn ServiceGatewayPolicy::validate(
  self : ServiceGatewayPolicy,
) -> Array[ModbusError] {
  let errors : Array[ModbusError] = []
  for i in 0..<self.rules.length() {
    if self.rules[i].span() < 1 {
      errors.push(InvalidQuantity)
    }
    for j in (i + 1)..<self.rules.length() {
      let left = self.rules[i]
      let right = self.rules[j]
      if left.source_unit() == right.source_unit() &&
        left.function() == right.function() &&
        left.source_start().to_int() <
        right.source_start().to_int() + right.span() &&
        right.source_start().to_int() <
        left.source_start().to_int() + left.span() &&
        left.priority() == right.priority() {
        errors.push(InvalidData)
      }
    }
  }
  errors
}

///|
/// Produce the stable rule table used in support bundles.
pub fn ServiceGatewayPolicy::export_rules(
  self : ServiceGatewayPolicy,
) -> Array[String] {
  let lines : Array[String] = []
  for rule in self.rules {
    lines.push(
      rule.id() +
      " unit=" +
      rule.source_unit().to_int().to_string() +
      "->" +
      rule.target_unit().to_int().to_string() +
      " fn=" +
      rule.function().to_int().to_string() +
      " range=" +
      rule.source_start().to_int().to_string() +
      "+" +
      rule.span().to_string() +
      " action=" +
      bridge_action_name(rule.action()) +
      " priority=" +
      rule.priority().to_string(),
    )
  }
  lines
}

///|
/// Fleet-level route table for selecting one policy by endpoint pair.
pub(all) struct GatewayPolicyTable {
  policies : Array[ServiceGatewayPolicy]
  max_policies : Int
}

///|
pub fn GatewayPolicyTable::new(
  max_policies? : Int = 128,
) -> Result[GatewayPolicyTable, ModbusError] {
  if max_policies < 1 {
    Err(InvalidData)
  } else {
    Ok({ policies: [], max_policies })
  }
}

///|
pub fn GatewayPolicyTable::count(self : GatewayPolicyTable) -> Int {
  self.policies.length()
}

///|
pub fn GatewayPolicyTable::add(
  self : GatewayPolicyTable,
  policy : ServiceGatewayPolicy,
) -> Result[Unit, ModbusError] {
  if self.policies.length() >= self.max_policies {
    return Err(CapacityExceeded)
  }
  for existing in self.policies {
    if existing.id() == policy.id() {
      return Err(InvalidData)
    }
  }
  self.policies.push(policy)
  Ok(())
}

///|
pub fn GatewayPolicyTable::find(
  self : GatewayPolicyTable,
  source : String,
  destination : String,
) -> ServiceGatewayPolicy? {
  for policy in self.policies {
    if policy.source() == source && policy.destination() == destination {
      return Some(policy)
    }
  }
  None
}

///|
pub fn GatewayPolicyTable::evaluate(
  self : GatewayPolicyTable,
  source : String,
  destination : String,
  frame : Frame,
) -> Result[BridgeDecision, ModbusError] {
  match self.find(source, destination) {
    Some(policy) => policy.evaluate(frame)
    None => Ok(BridgeDecision::new(DenyBridge, "route-not-configured"))
  }
}

///|
pub fn GatewayPolicyTable::routes(self : GatewayPolicyTable) -> Array[String] {
  let result : Array[String] = []
  for policy in self.policies {
    result.push(policy.source() + "->" + policy.destination())
  }
  result
}
