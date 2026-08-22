///|
/// Severity assigned to an operational alarm.
pub(all) enum AlarmSeverity {
  Informational
  Warning
  Critical
} derive(Debug, Eq)

///|
/// Comparison used by an alarm rule.
pub(all) enum AlarmCondition {
  Below
  AtOrBelow
  Equal
  NotEqual
  AtOrAbove
  Above
  Outside
  Inside
} derive(Debug, Eq)

///|
/// Lifecycle state of an alarm instance.
pub(all) enum AlarmState {
  Normal
  Pending
  Active
  Acknowledged
  Clearing
  Shelved
} derive(Debug, Eq)

///|
pub fn alarm_severity_name(value : AlarmSeverity) -> String {
  match value {
    Informational => "informational"
    Warning => "warning"
    Critical => "critical"
  }
}

///|
pub fn alarm_condition_name(value : AlarmCondition) -> String {
  match value {
    Below => "below"
    AtOrBelow => "at-or-below"
    Equal => "equal"
    NotEqual => "not-equal"
    AtOrAbove => "at-or-above"
    Above => "above"
    Outside => "outside"
    Inside => "inside"
  }
}

///|
pub fn alarm_state_name(value : AlarmState) -> String {
  match value {
    Normal => "normal"
    Pending => "pending"
    Active => "active"
    Acknowledged => "acknowledged"
    Clearing => "clearing"
    Shelved => "shelved"
  }
}

///|
/// A declarative threshold rule attached to a profile point.
pub(all) struct AlarmRule {
  id : String
  point_id : String
  condition : AlarmCondition
  low : Int
  high : Int
  severity : AlarmSeverity
  activation_delay : Int
  clear_delay : Int
  hysteresis : Int
  mut enabled : Bool
}

///|
pub fn AlarmRule::new(
  id : String,
  point_id : String,
  condition : AlarmCondition,
  low : Int,
  high : Int,
  severity : AlarmSeverity,
  activation_delay? : Int = 0,
  clear_delay? : Int = 0,
  hysteresis? : Int = 0,
) -> Result[AlarmRule, ModbusError] {
  if id == "" || point_id == "" || low > high {
    return Err(InvalidData)
  }
  if activation_delay < 0 || clear_delay < 0 || hysteresis < 0 {
    return Err(InvalidData)
  }
  Ok({
    id,
    point_id,
    condition,
    low,
    high,
    severity,
    activation_delay,
    clear_delay,
    hysteresis,
    enabled: true,
  })
}

///|
pub fn AlarmRule::id(self : AlarmRule) -> String {
  self.id
}

///|
pub fn AlarmRule::point_id(self : AlarmRule) -> String {
  self.point_id
}

///|
pub fn AlarmRule::condition(self : AlarmRule) -> AlarmCondition {
  self.condition
}

///|
pub fn AlarmRule::low(self : AlarmRule) -> Int {
  self.low
}

///|
pub fn AlarmRule::high(self : AlarmRule) -> Int {
  self.high
}

///|
pub fn AlarmRule::severity(self : AlarmRule) -> AlarmSeverity {
  self.severity
}

///|
pub fn AlarmRule::activation_delay(self : AlarmRule) -> Int {
  self.activation_delay
}

///|
pub fn AlarmRule::clear_delay(self : AlarmRule) -> Int {
  self.clear_delay
}

///|
pub fn AlarmRule::hysteresis(self : AlarmRule) -> Int {
  self.hysteresis
}

///|
pub fn AlarmRule::enabled(self : AlarmRule) -> Bool {
  self.enabled
}

///|
pub fn AlarmRule::set_enabled(self : AlarmRule, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
pub fn AlarmRule::matches(self : AlarmRule, value : Int) -> Bool {
  if !self.enabled {
    return false
  }
  match self.condition {
    Below => value < self.low
    AtOrBelow => value <= self.low
    Equal => value == self.low
    NotEqual => value != self.low
    AtOrAbove => value >= self.high
    Above => value > self.high
    Outside => value < self.low || value > self.high
    Inside => value > self.low && value < self.high
  }
}

///|
pub fn AlarmRule::clear_matches(self : AlarmRule, value : Int) -> Bool {
  if !self.enabled {
    return true
  }
  let low = self.low + self.hysteresis
  let high = self.high - self.hysteresis
  match self.condition {
    Below | AtOrBelow => value >= low
    Equal => value != self.low
    NotEqual => value == self.low
    AtOrAbove | Above => value <= high
    Outside => value >= low && value <= high
    Inside => value <= low || value >= high
  }
}

///|
pub fn AlarmRule::summary(self : AlarmRule) -> String {
  self.id +
  " point=" +
  self.point_id +
  " condition=" +
  alarm_condition_name(self.condition) +
  " low=" +
  self.low.to_string() +
  " high=" +
  self.high.to_string() +
  " severity=" +
  alarm_severity_name(self.severity)
}

///|
/// An event emitted when an alarm lifecycle changes.
pub(all) struct AlarmEvent {
  sequence : Int
  rule_id : String
  point_id : String
  state : AlarmState
  value : Int
  timestamp : Int
  severity : AlarmSeverity
  message : String
} derive(Debug)

///|
pub fn AlarmEvent::sequence(self : AlarmEvent) -> Int {
  self.sequence
}

///|
pub fn AlarmEvent::rule_id(self : AlarmEvent) -> String {
  self.rule_id
}

///|
pub fn AlarmEvent::point_id(self : AlarmEvent) -> String {
  self.point_id
}

///|
pub fn AlarmEvent::state(self : AlarmEvent) -> AlarmState {
  self.state
}

///|
pub fn AlarmEvent::value(self : AlarmEvent) -> Int {
  self.value
}

///|
pub fn AlarmEvent::timestamp(self : AlarmEvent) -> Int {
  self.timestamp
}

///|
pub fn AlarmEvent::severity(self : AlarmEvent) -> AlarmSeverity {
  self.severity
}

///|
pub fn AlarmEvent::message(self : AlarmEvent) -> String {
  self.message
}

///|
pub fn AlarmEvent::summary(self : AlarmEvent) -> String {
  self.rule_id +
  " " +
  alarm_state_name(self.state) +
  " value=" +
  self.value.to_string() +
  " at=" +
  self.timestamp.to_string()
}

///|
/// Internal state retained for one rule.
pub(all) struct AlarmInstance {
  rule : AlarmRule
  mut state : AlarmState
  mut pending_since : Int?
  mut clearing_since : Int?
  mut last_value : Int
  mut last_timestamp : Int
  mut transitions : Int
  mut acknowledger : String?
}

///|
pub fn AlarmInstance::new(rule : AlarmRule) -> AlarmInstance {
  {
    rule,
    state: Normal,
    pending_since: None,
    clearing_since: None,
    last_value: 0,
    last_timestamp: 0,
    transitions: 0,
    acknowledger: None,
  }
}

///|
pub fn AlarmInstance::rule(self : AlarmInstance) -> AlarmRule {
  self.rule
}

///|
pub fn AlarmInstance::id(self : AlarmInstance) -> String {
  self.rule.id()
}

///|
pub fn AlarmInstance::point_id(self : AlarmInstance) -> String {
  self.rule.point_id()
}

///|
pub fn AlarmInstance::state(self : AlarmInstance) -> AlarmState {
  self.state
}

///|
pub fn AlarmInstance::last_value(self : AlarmInstance) -> Int {
  self.last_value
}

///|
pub fn AlarmInstance::last_timestamp(self : AlarmInstance) -> Int {
  self.last_timestamp
}

///|
pub fn AlarmInstance::transitions(self : AlarmInstance) -> Int {
  self.transitions
}

///|
pub fn AlarmInstance::acknowledger(self : AlarmInstance) -> String? {
  self.acknowledger
}

///|
pub fn AlarmInstance::is_active(self : AlarmInstance) -> Bool {
  self.state == Active || self.state == Acknowledged || self.state == Clearing
}

///|
pub fn AlarmInstance::acknowledge(
  self : AlarmInstance,
  operator : String,
) -> Result[Unit, ModbusError] {
  if operator == "" {
    return Err(InvalidData)
  }
  if self.state == Active {
    self.state = Acknowledged
    self.acknowledger = Some(operator)
    self.transitions += 1
    Ok(())
  } else if self.state == Acknowledged {
    self.acknowledger = Some(operator)
    Ok(())
  } else {
    Err(InvalidData)
  }
}

///|
pub fn AlarmInstance::shelve(self : AlarmInstance) -> Result[Unit, ModbusError] {
  if self.state == Normal {
    Err(InvalidData)
  } else {
    self.state = Shelved
    self.transitions += 1
    Ok(())
  }
}

///|
pub fn AlarmInstance::unshelve(self : AlarmInstance) -> Unit {
  if self.state == Shelved {
    self.state = Normal
    self.pending_since = None
    self.clearing_since = None
    self.acknowledger = None
    self.transitions += 1
  }
}

///|
/// A deterministic transition result used by polling and UI layers.
pub(all) enum AlarmTransition {
  Unchanged(AlarmState)
  Changed(AlarmEvent)
} derive(Debug)

///|
fn alarm_event(
  instance : AlarmInstance,
  state : AlarmState,
  value : Int,
  timestamp : Int,
  sequence : Int,
) -> AlarmEvent {
  {
    sequence,
    rule_id: instance.id(),
    point_id: instance.point_id(),
    state,
    value,
    timestamp,
    severity: instance.rule().severity(),
    message: instance.id() + " -> " + alarm_state_name(state),
  }
}

///|
fn alarm_emit_transition(
  instance : AlarmInstance,
  old : AlarmState,
  value : Int,
  timestamp : Int,
  sequence : Int,
) -> AlarmTransition {
  if old == instance.state() {
    Unchanged(old)
  } else {
    Changed(alarm_event(instance, instance.state(), value, timestamp, sequence))
  }
}

///|
/// Evaluate one new sample and update the instance lifecycle.
pub fn AlarmInstance::evaluate(
  self : AlarmInstance,
  value : Int,
  timestamp : Int,
  sequence : Int,
) -> AlarmTransition {
  let old = self.state
  if timestamp < self.last_timestamp {
    return Unchanged(self.state)
  }
  self.last_value = value
  self.last_timestamp = timestamp
  if self.state == Shelved {
    return Unchanged(self.state)
  }
  if !self.rule.enabled() {
    self.state = Normal
    self.pending_since = None
    self.clearing_since = None
    return alarm_emit_transition(self, old, value, timestamp, sequence)
  }
  match self.state {
    Normal =>
      if self.rule.matches(value) {
        if self.rule.activation_delay() == 0 {
          self.state = Active
          self.transitions += 1
        } else {
          self.state = Pending
          self.pending_since = Some(timestamp)
          self.transitions += 1
        }
      }
    Pending =>
      if !self.rule.matches(value) {
        self.state = Normal
        self.pending_since = None
        self.transitions += 1
      } else if self.pending_since is Some(start) &&
        timestamp - start >= self.rule.activation_delay() {
        self.state = Active
        self.pending_since = None
        self.transitions += 1
      }
    Active | Acknowledged =>
      if self.rule.clear_matches(value) {
        if self.rule.clear_delay() == 0 {
          self.state = Normal
          self.acknowledger = None
          self.transitions += 1
        } else {
          self.state = Clearing
          self.clearing_since = Some(timestamp)
          self.transitions += 1
        }
      }
    Clearing =>
      if !self.rule.clear_matches(value) {
        self.state = Active
        self.clearing_since = None
        self.transitions += 1
      } else if self.clearing_since is Some(start) &&
        timestamp - start >= self.rule.clear_delay() {
        self.state = Normal
        self.clearing_since = None
        self.acknowledger = None
        self.transitions += 1
      }
    Shelved => ()
  }
  alarm_emit_transition(self, old, value, timestamp, sequence)
}

///|
/// A bounded alarm engine suitable for a device server or polling loop.
pub(all) struct AlarmEngine {
  instances : Array[AlarmInstance]
  events : Array[AlarmEvent]
  max_events : Int
  mut next_sequence : Int
}

///|
pub fn AlarmEngine::new(
  max_events? : Int = 2048,
) -> Result[AlarmEngine, ModbusError] {
  if max_events < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ instances: [], events: [], max_events, next_sequence: 1 })
  }
}

///|
pub fn AlarmEngine::rule_count(self : AlarmEngine) -> Int {
  self.instances.length()
}

///|
pub fn AlarmEngine::event_count(self : AlarmEngine) -> Int {
  self.events.length()
}

///|
pub fn AlarmEngine::add_rule(
  self : AlarmEngine,
  rule : AlarmRule,
) -> Result[Unit, ModbusError] {
  for instance in self.instances {
    if instance.id() == rule.id() {
      return Err(InvalidData)
    }
  }
  self.instances.push(AlarmInstance::new(rule))
  Ok(())
}

///|
pub fn AlarmEngine::remove_rule(
  self : AlarmEngine,
  rule_id : String,
) -> Result[Unit, ModbusError] {
  for index, instance in self.instances {
    if instance.id() == rule_id {
      ignore(self.instances.remove(index))
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
pub fn AlarmEngine::instance(
  self : AlarmEngine,
  rule_id : String,
) -> AlarmInstance? {
  for instance in self.instances {
    if instance.id() == rule_id {
      return Some(instance)
    }
  }
  None
}

///|
fn AlarmEngine::store_event(self : AlarmEngine, event : AlarmEvent) -> Unit {
  if self.events.length() >= self.max_events {
    ignore(self.events.remove(0))
  }
  self.events.push(event)
}

///|
pub fn AlarmEngine::evaluate(
  self : AlarmEngine,
  point_id : String,
  value : Int,
  timestamp : Int,
) -> Result[Array[AlarmEvent], ModbusError] {
  let result : Array[AlarmEvent] = []
  for index, instance in self.instances {
    if instance.point_id() == point_id {
      let transition = instance.evaluate(value, timestamp, self.next_sequence)
      self.instances[index] = instance
      self.next_sequence += 1
      match transition {
        Unchanged(_) => ()
        Changed(event) => {
          self.store_event(event)
          result.push(event)
        }
      }
    }
  }
  Ok(result)
}

///|
pub fn AlarmEngine::acknowledge(
  self : AlarmEngine,
  rule_id : String,
  operator : String,
  timestamp : Int,
) -> Result[AlarmEvent, ModbusError] {
  for index, instance in self.instances {
    if instance.id() == rule_id {
      match instance.acknowledge(operator) {
        Err(error) => return Err(error)
        Ok(_) => {
          self.instances[index] = instance
          self.next_sequence += 1
          let event = alarm_event(
            instance,
            Acknowledged,
            instance.last_value(),
            timestamp,
            self.next_sequence,
          )
          self.store_event(event)
          return Ok(event)
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn AlarmEngine::shelve(
  self : AlarmEngine,
  rule_id : String,
  timestamp : Int,
) -> Result[AlarmEvent, ModbusError] {
  for index, instance in self.instances {
    if instance.id() == rule_id {
      match instance.shelve() {
        Err(error) => return Err(error)
        Ok(_) => {
          self.instances[index] = instance
          self.next_sequence += 1
          let event = alarm_event(
            instance,
            Shelved,
            instance.last_value(),
            timestamp,
            self.next_sequence,
          )
          self.store_event(event)
          return Ok(event)
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn AlarmEngine::unshelve(
  self : AlarmEngine,
  rule_id : String,
  timestamp : Int,
) -> Result[AlarmEvent, ModbusError] {
  for index, instance in self.instances {
    if instance.id() == rule_id {
      instance.unshelve()
      self.instances[index] = instance
      self.next_sequence += 1
      let event = alarm_event(
        instance,
        Normal,
        instance.last_value(),
        timestamp,
        self.next_sequence,
      )
      self.store_event(event)
      return Ok(event)
    }
  }
  Err(InvalidData)
}

///|
pub fn AlarmEngine::active(self : AlarmEngine) -> Array[AlarmInstance] {
  let result : Array[AlarmInstance] = []
  for instance in self.instances {
    if instance.is_active() {
      result.push(instance)
    }
  }
  result
}

///|
pub fn AlarmEngine::active_count(self : AlarmEngine) -> Int {
  self.active().length()
}

///|
pub fn AlarmEngine::events(self : AlarmEngine) -> Array[AlarmEvent] {
  let result : Array[AlarmEvent] = []
  for event in self.events {
    result.push(event)
  }
  result
}

///|
pub fn AlarmEngine::events_for_point(
  self : AlarmEngine,
  point_id : String,
) -> Array[AlarmEvent] {
  let result : Array[AlarmEvent] = []
  for event in self.events {
    if event.point_id() == point_id {
      result.push(event)
    }
  }
  result
}

///|
pub fn AlarmEngine::clear_events(self : AlarmEngine) -> Unit {
  self.events.clear()
}

///|
pub fn AlarmEngine::reset(self : AlarmEngine) -> Unit {
  for index, instance in self.instances {
    let rule = instance.rule()
    self.instances[index] = AlarmInstance::new(rule)
  }
  self.events.clear()
  self.next_sequence = 1
}

///|
pub fn AlarmEngine::summary(self : AlarmEngine) -> String {
  "rules=" +
  self.rule_count().to_string() +
  " active=" +
  self.active_count().to_string() +
  " events=" +
  self.event_count().to_string()
}
