///|
/// Quality test applied to a decoded point value.
pub(all) enum QualityTest {
  RangeTest
  FreshnessTest
  StepTest
  DuplicateTest
  EnumTest
  RequiredTest
} derive(Debug, Eq)

///|
/// Decision produced by a quality pipeline.
pub(all) enum QualityDecision {
  QualityAccepted
  QualitySubstituted
  QualityRejected
  QualityDeferred
} derive(Debug, Eq)

///|
/// A field-level quality rule.
pub(all) struct QualityRule {
  id : String
  point_id : String
  check_kind : QualityTest
  lower : Int?
  upper : Int?
  limit : Int
  allowed : Array[Int]
  mut enabled : Bool
}

///|
pub fn QualityRule::new(
  id : String,
  point_id : String,
  check_kind : QualityTest,
  lower? : Int = 0,
  upper? : Int = 0,
  limit? : Int = 0,
) -> Result[QualityRule, ModbusError] {
  if id == "" || point_id == "" || limit < 0 {
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
    point_id,
    check_kind,
    lower: selected_lower,
    upper: selected_upper,
    limit,
    allowed: [],
    enabled: true,
  })
}

///|
pub fn QualityRule::id(self : QualityRule) -> String {
  self.id
}

///|
pub fn QualityRule::point_id(self : QualityRule) -> String {
  self.point_id
}

///|
pub fn QualityRule::check_kind(self : QualityRule) -> QualityTest {
  self.check_kind
}

///|
pub fn QualityRule::lower(self : QualityRule) -> Int? {
  self.lower
}

///|
pub fn QualityRule::upper(self : QualityRule) -> Int? {
  self.upper
}

///|
pub fn QualityRule::limit(self : QualityRule) -> Int {
  self.limit
}

///|
pub fn QualityRule::enabled(self : QualityRule) -> Bool {
  self.enabled
}

///|
pub fn QualityRule::set_enabled(self : QualityRule, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
pub fn QualityRule::allow_value(
  self : QualityRule,
  value : Int,
) -> Result[Unit, ModbusError] {
  if self.allowed.length() >= 256 {
    return Err(CapacityExceeded)
  }
  for existing in self.allowed {
    if existing == value {
      return Ok(())
    }
  }
  self.allowed.push(value)
  Ok(())
}

///|
pub fn quality_test_name(kind : QualityTest) -> String {
  match kind {
    RangeTest => "range"
    FreshnessTest => "freshness"
    StepTest => "step"
    DuplicateTest => "duplicate"
    EnumTest => "enum"
    RequiredTest => "required"
  }
}

///|
/// One quality evaluation with stable evidence for the operator.
pub(all) struct QualityFinding {
  rule_id : String
  point_id : String
  check_kind : QualityTest
  decision : QualityDecision
  value : Int
  timestamp : Int
  message : String
}

///|
pub fn QualityFinding::new(
  rule : QualityRule,
  decision : QualityDecision,
  value : Int,
  timestamp : Int,
  message : String,
) -> Result[QualityFinding, ModbusError] {
  if timestamp < 0 || message == "" {
    return Err(InvalidData)
  }
  Ok({
    rule_id: rule.id(),
    point_id: rule.point_id(),
    check_kind: rule.check_kind(),
    decision,
    value,
    timestamp,
    message,
  })
}

///|
pub fn QualityFinding::rule_id(self : QualityFinding) -> String {
  self.rule_id
}

///|
pub fn QualityFinding::point_id(self : QualityFinding) -> String {
  self.point_id
}

///|
pub fn QualityFinding::check_kind(self : QualityFinding) -> QualityTest {
  self.check_kind
}

///|
pub fn QualityFinding::decision(self : QualityFinding) -> QualityDecision {
  self.decision
}

///|
pub fn QualityFinding::value(self : QualityFinding) -> Int {
  self.value
}

///|
pub fn QualityFinding::timestamp(self : QualityFinding) -> Int {
  self.timestamp
}

///|
pub fn QualityFinding::message(self : QualityFinding) -> String {
  self.message
}

///|
/// Evaluate a rule against current and previous observations.
pub fn QualityRule::evaluate(
  self : QualityRule,
  value : Int,
  timestamp : Int,
  previous : Int?,
  previous_timestamp : Int?,
) -> Result[QualityFinding, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  if !self.enabled {
    return QualityFinding::new(
      self,
      QualityDeferred,
      value,
      timestamp,
      "rule-disabled",
    )
  }
  match self.check_kind {
    RangeTest => {
      match self.lower {
        Some(low) =>
          if value < low {
            return QualityFinding::new(
              self,
              QualityRejected,
              value,
              timestamp,
              "below-lower-bound",
            )
          }
        None => ()
      }
      match self.upper {
        Some(high) =>
          if value > high {
            return QualityFinding::new(
              self,
              QualityRejected,
              value,
              timestamp,
              "above-upper-bound",
            )
          }
        None => ()
      }
      QualityFinding::new(
        self,
        QualityAccepted,
        value,
        timestamp,
        "within-range",
      )
    }
    FreshnessTest =>
      match previous_timestamp {
        Some(last) =>
          if timestamp - last > self.limit {
            QualityFinding::new(
              self,
              QualitySubstituted,
              value,
              timestamp,
              "stale-input",
            )
          } else {
            QualityFinding::new(
              self,
              QualityAccepted,
              value,
              timestamp,
              "fresh-input",
            )
          }
        None =>
          QualityFinding::new(
            self,
            QualityDeferred,
            value,
            timestamp,
            "no-baseline",
          )
      }
    StepTest =>
      match previous {
        Some(last) =>
          if (value - last).abs() > self.limit {
            QualityFinding::new(
              self,
              QualityRejected,
              value,
              timestamp,
              "step-too-large",
            )
          } else {
            QualityFinding::new(
              self,
              QualityAccepted,
              value,
              timestamp,
              "step-ok",
            )
          }
        None =>
          QualityFinding::new(
            self,
            QualityDeferred,
            value,
            timestamp,
            "no-baseline",
          )
      }
    DuplicateTest =>
      match previous {
        Some(last) =>
          if value == last {
            QualityFinding::new(
              self,
              QualitySubstituted,
              value,
              timestamp,
              "duplicate-value",
            )
          } else {
            QualityFinding::new(
              self,
              QualityAccepted,
              value,
              timestamp,
              "new-value",
            )
          }
        None =>
          QualityFinding::new(
            self,
            QualityAccepted,
            value,
            timestamp,
            "first-value",
          )
      }
    EnumTest => {
      for allowed in self.allowed {
        if value == allowed {
          return QualityFinding::new(
            self,
            QualityAccepted,
            value,
            timestamp,
            "allowed-enum",
          )
        }
      }
      QualityFinding::new(
        self,
        QualityRejected,
        value,
        timestamp,
        "unknown-enum",
      )
    }
    RequiredTest =>
      QualityFinding::new(self, QualityAccepted, value, timestamp, "present")
  }
}

///|
/// Ordered rules and recent findings for a point pipeline.
pub(all) struct QualityPipeline {
  rules : Array[QualityRule]
  findings : Array[QualityFinding]
  max_findings : Int
}

///|
pub fn QualityPipeline::new(
  max_findings? : Int = 4096,
) -> Result[QualityPipeline, ModbusError] {
  if max_findings < 1 {
    Err(InvalidData)
  } else {
    Ok({ rules: [], findings: [], max_findings })
  }
}

///|
pub fn QualityPipeline::rule_count(self : QualityPipeline) -> Int {
  self.rules.length()
}

///|
pub fn QualityPipeline::finding_count(self : QualityPipeline) -> Int {
  self.findings.length()
}

///|
pub fn QualityPipeline::add_rule(
  self : QualityPipeline,
  rule : QualityRule,
) -> Result[Unit, ModbusError] {
  for existing in self.rules {
    if existing.id() == rule.id() {
      return Err(InvalidData)
    }
  }
  self.rules.push(rule)
  Ok(())
}

///|
pub fn QualityPipeline::rule(
  self : QualityPipeline,
  id : String,
) -> QualityRule? {
  for rule in self.rules {
    if rule.id() == id {
      return Some(rule)
    }
  }
  None
}

///|
/// Evaluate all rules for a point and retain every finding.
pub fn QualityPipeline::evaluate(
  self : QualityPipeline,
  point_id : String,
  value : Int,
  timestamp : Int,
  previous? : Int? = None,
  previous_timestamp? : Int? = None,
) -> Result[QualityDecision, ModbusError] {
  if point_id == "" || timestamp < 0 {
    return Err(InvalidData)
  }
  let selected_previous = previous
  let selected_timestamp = previous_timestamp
  let mut decision = QualityAccepted
  for rule in self.rules {
    if rule.point_id() != point_id {
      continue
    }
    let finding = match
      rule.evaluate(value, timestamp, selected_previous, selected_timestamp) {
      Ok(item) => item
      Err(error) => return Err(error)
    }
    if self.findings.length() >= self.max_findings {
      ignore(self.findings.remove(0))
    }
    self.findings.push(finding)
    match finding.decision() {
      QualityRejected => return Ok(QualityRejected)
      QualitySubstituted =>
        if decision == QualityAccepted {
          decision = QualitySubstituted
        }
      QualityDeferred =>
        if decision == QualityAccepted {
          decision = QualityDeferred
        }
      QualityAccepted => ()
    }
  }
  Ok(decision)
}

///|
pub fn QualityPipeline::findings_for(
  self : QualityPipeline,
  point_id : String,
) -> Array[QualityFinding] {
  let result : Array[QualityFinding] = []
  for finding in self.findings {
    if finding.point_id() == point_id {
      result.push(finding)
    }
  }
  result
}

///|
pub fn QualityPipeline::rejected(self : QualityPipeline) -> Int {
  let mut count = 0
  for finding in self.findings {
    if finding.decision() == QualityRejected {
      count += 1
    }
  }
  count
}

///|
pub fn QualityPipeline::substituted(self : QualityPipeline) -> Int {
  let mut count = 0
  for finding in self.findings {
    if finding.decision() == QualitySubstituted {
      count += 1
    }
  }
  count
}

///|
pub fn quality_decision_name(decision : QualityDecision) -> String {
  match decision {
    QualityAccepted => "accepted"
    QualitySubstituted => "substituted"
    QualityRejected => "rejected"
    QualityDeferred => "deferred"
  }
}

///|
/// A compact quality summary for one point.
pub(all) struct QualitySummary {
  accepted : Int
  substituted : Int
  rejected : Int
  deferred : Int
}

///|
pub fn QualityPipeline::summary(
  self : QualityPipeline,
  point_id : String,
) -> QualitySummary {
  let mut accepted = 0
  let mut substituted = 0
  let mut rejected = 0
  let mut deferred = 0
  for finding in self.findings {
    if finding.point_id() == point_id {
      match finding.decision() {
        QualityAccepted => accepted += 1
        QualitySubstituted => substituted += 1
        QualityRejected => rejected += 1
        QualityDeferred => deferred += 1
      }
    }
  }
  { accepted, substituted, rejected, deferred }
}

///|
pub fn QualitySummary::accepted(self : QualitySummary) -> Int {
  self.accepted
}

///|
pub fn QualitySummary::substituted(self : QualitySummary) -> Int {
  self.substituted
}

///|
pub fn QualitySummary::rejected(self : QualitySummary) -> Int {
  self.rejected
}

///|
pub fn QualitySummary::deferred(self : QualitySummary) -> Int {
  self.deferred
}
