///|
/// Address mapping rule for a protocol gateway.
pub(all) struct GatewayRule {
  source_unit : Byte
  target_unit : Byte
  function : Byte
  source_start : UInt16
  target_start : UInt16
  span : Int
  mut enabled : Bool
}

///|
pub fn GatewayRule::new(
  source_unit : Byte,
  target_unit : Byte,
  function : Byte,
  source_start : UInt16,
  target_start : UInt16,
  span : Int,
) -> Result[GatewayRule, ModbusError] {
  if !is_valid_unit_id(source_unit) ||
    !is_valid_unit_id(target_unit, broadcast=false) {
    return Err(InvalidUnitId)
  }
  if span < 1 ||
    !valid_address_range(source_start, span) ||
    !valid_address_range(target_start, span) {
    return Err(InvalidAddress)
  }
  Ok({
    source_unit,
    target_unit,
    function,
    source_start,
    target_start,
    span,
    enabled: true,
  })
}

///|
pub fn GatewayRule::matches(self : GatewayRule, frame : Frame) -> Bool {
  if !self.enabled ||
    frame.unit_id != self.source_unit ||
    ordinary_function(frame.pdu.function) != self.function {
    return false
  }
  match first_address(frame) {
    Some(address) =>
      address.to_int() >= self.source_start.to_int() &&
      address.to_int() < self.source_start.to_int() + self.span
    None => true
  }
}

///|
pub fn GatewayRule::enable(self : GatewayRule, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
fn first_address(frame : Frame) -> UInt16? {
  if frame.pdu.data.length() < 2 {
    None
  } else {
    Some((frame.pdu.data[0].to_uint16() << 8) | frame.pdu.data[1].to_uint16())
  }
}

///|
/// A deterministic frame gateway that rewrites unit ids and register/coil addresses.
pub struct Gateway {
  rules : Array[GatewayRule]
  mut forwarded : Int
  mut rejected : Int
  mut translated : Int
}

///|
pub fn Gateway::new() -> Gateway {
  { rules: [], forwarded: 0, rejected: 0, translated: 0 }
}

///|
pub fn Gateway::add_rule(
  self : Gateway,
  rule : GatewayRule,
) -> Result[Unit, ModbusError] {
  if self.rules.length() >= 256 {
    Err(CapacityExceeded)
  } else {
    self.rules.push(rule)
    Ok(())
  }
}

///|
pub fn Gateway::rule_count(self : Gateway) -> Int {
  self.rules.length()
}

///|
pub fn Gateway::rules(self : Gateway) -> Array[GatewayRule] {
  let out : Array[GatewayRule] = []
  for rule in self.rules {
    out.push(rule)
  }
  out
}

///|
/// Translate one request according to the first matching rule.
pub fn Gateway::translate(
  self : Gateway,
  frame : Frame,
) -> Result[Frame, ModbusError] {
  for rule in self.rules {
    if rule.matches(frame) {
      self.forwarded += 1
      match translate_with_rule(frame, rule) {
        Ok(value) => {
          self.translated += 1
          return Ok(value)
        }
        Err(error) => {
          self.rejected += 1
          return Err(error)
        }
      }
    }
  }
  self.rejected += 1
  Err(InvalidAddress)
}

///|
fn translate_with_rule(
  frame : Frame,
  rule : GatewayRule,
) -> Result[Frame, ModbusError] {
  let data = copy_bytes(frame.pdu.data)
  match first_address(frame) {
    None => Ok(with_unit(frame, rule.target_unit))
    Some(address) => {
      let offset = address.to_int() - rule.source_start.to_int()
      let target = rule.target_start.to_int() + offset
      if target < 0 || target > 65535 {
        Err(InvalidAddress)
      } else {
        data[0] = (target / 256).to_byte()
        data[1] = target.to_byte()
        Ok({
          unit_id: rule.target_unit,
          pdu: { function: frame.pdu.function, data },
        })
      }
    }
  }
}

///|
/// Translate a response back to the source address space.
pub fn Gateway::reverse(
  self : Gateway,
  request : Frame,
  response : Frame,
) -> Result[Frame, ModbusError] {
  if response.unit_id != request.unit_id {
    return Err(UnitMismatch)
  }
  for rule in self.rules {
    if rule.source_unit == request.unit_id &&
      rule.target_unit == response.unit_id &&
      rule.function == ordinary_function(request.pdu.function) {
      return Ok(with_unit(response, rule.source_unit))
    }
  }
  Ok(response)
}

///|
pub fn Gateway::forwarded_count(self : Gateway) -> Int {
  self.forwarded
}

///|
pub fn Gateway::rejected_count(self : Gateway) -> Int {
  self.rejected
}

///|
pub fn Gateway::translated_count(self : Gateway) -> Int {
  self.translated
}

///|
pub fn Gateway::reset_metrics(self : Gateway) -> Unit {
  self.forwarded = 0
  self.rejected = 0
  self.translated = 0
}

///|
/// A gateway route that combines a rule set, client, and virtual device.
pub(all) struct GatewayRoute {
  name : String
  gateway : Gateway
  device : Device
  client : Client
}

///|
pub fn GatewayRoute::new(
  name : String,
  mode : Mode,
  device : Device,
) -> GatewayRoute {
  { name, gateway: Gateway::new(), device, client: Client::new(mode) }
}

///|
pub fn GatewayRoute::add_rule(
  self : GatewayRoute,
  rule : GatewayRule,
) -> Result[Unit, ModbusError] {
  self.gateway.add_rule(rule)
}

///|
pub fn GatewayRoute::exchange(
  self : GatewayRoute,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let translated = match self.gateway.translate(request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let prepared = match self.client.begin(translated) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let response = match self.device.handle(translated) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.client.accept_frame(prepared, 0, response)
}

///|
pub fn GatewayRoute::name(self : GatewayRoute) -> String {
  self.name
}

///|
pub fn GatewayRoute::metrics(self : GatewayRoute) -> (Int, Int, Int) {
  (
    self.gateway.forwarded_count(),
    self.gateway.rejected_count(),
    self.gateway.translated_count(),
  )
}

///|
/// Return whether a gateway rule can safely carry a function code.
pub fn gateway_function_supported(function : Byte) -> Bool {
  function != 0 && supported_function(function)
}
