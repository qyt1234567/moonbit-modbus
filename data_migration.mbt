///|
/// Lifecycle state of a configuration migration.
pub(all) enum MigrationState {
  MigrationPlanned
  MigrationRunning
  MigrationApplied
  MigrationRolledBack
  MigrationFailed
} derive(Debug, Eq)

///|
/// Operation used by a migration step.
pub(all) enum MigrationOperation {
  AddSetting
  RemoveSetting
  RenameSetting
  ReplaceSetting
  ValidateSetting
} derive(Debug, Eq)

///|
/// One deterministic configuration change with a rollback value.
pub(all) struct MigrationStep {
  id : String
  operation : MigrationOperation
  key : String
  value : String
  rollback_value : String?
  order : Int
  mut applied : Bool
}

///|
pub fn MigrationStep::new(
  id : String,
  operation : MigrationOperation,
  key : String,
  value : String,
  order : Int,
  rollback_value? : String = "",
) -> Result[MigrationStep, ModbusError] {
  if id == "" || key == "" || order < 0 {
    return Err(InvalidData)
  }
  let selected_rollback = if rollback_value == "" {
    None
  } else {
    Some(rollback_value)
  }
  Ok({
    id,
    operation,
    key,
    value,
    rollback_value: selected_rollback,
    order,
    applied: false,
  })
}

///|
pub fn MigrationStep::id(self : MigrationStep) -> String {
  self.id
}

///|
pub fn MigrationStep::operation(self : MigrationStep) -> MigrationOperation {
  self.operation
}

///|
pub fn MigrationStep::key(self : MigrationStep) -> String {
  self.key
}

///|
pub fn MigrationStep::value(self : MigrationStep) -> String {
  self.value
}

///|
pub fn MigrationStep::rollback_value(self : MigrationStep) -> String? {
  self.rollback_value
}

///|
pub fn MigrationStep::order(self : MigrationStep) -> Int {
  self.order
}

///|
pub fn MigrationStep::applied(self : MigrationStep) -> Bool {
  self.applied
}

///|
pub fn MigrationStep::mark_applied(self : MigrationStep) -> Unit {
  self.applied = true
}

///|
pub fn MigrationStep::mark_pending(self : MigrationStep) -> Unit {
  self.applied = false
}

///|
pub fn migration_operation_name(operation : MigrationOperation) -> String {
  match operation {
    AddSetting => "add"
    RemoveSetting => "remove"
    RenameSetting => "rename"
    ReplaceSetting => "replace"
    ValidateSetting => "validate"
  }
}

///|
/// A copy-on-write key/value configuration snapshot.
pub(all) struct MigrationSnapshot {
  version : Int
  entries : Array[(String, String)]
  timestamp : Int
}

///|
pub fn MigrationSnapshot::new(
  version : Int,
  timestamp : Int,
) -> Result[MigrationSnapshot, ModbusError] {
  if version < 0 || timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ version, entries: [], timestamp })
  }
}

///|
pub fn MigrationSnapshot::version(self : MigrationSnapshot) -> Int {
  self.version
}

///|
pub fn MigrationSnapshot::timestamp(self : MigrationSnapshot) -> Int {
  self.timestamp
}

///|
pub fn MigrationSnapshot::length(self : MigrationSnapshot) -> Int {
  self.entries.length()
}

///|
pub fn MigrationSnapshot::get(
  self : MigrationSnapshot,
  key : String,
) -> String? {
  for entry in self.entries {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn MigrationSnapshot::put(
  self : MigrationSnapshot,
  key : String,
  value : String,
) -> Result[Unit, ModbusError] {
  if key == "" {
    return Err(InvalidData)
  }
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == key {
      self.entries[i] = (key, value)
      return Ok(())
    }
  }
  self.entries.push((key, value))
  Ok(())
}

///|
pub fn MigrationSnapshot::remove(
  self : MigrationSnapshot,
  key : String,
) -> Result[String, ModbusError] {
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == key {
      return Ok(self.entries.remove(i).1)
    }
  }
  Err(InvalidData)
}

///|
pub fn MigrationSnapshot::keys(self : MigrationSnapshot) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    result.push(entry.0)
  }
  result
}

///|
/// Ordered migration plan with transactional execution state.
pub(all) struct MigrationPlan {
  id : String
  from_version : Int
  to_version : Int
  steps : Array[MigrationStep]
  max_steps : Int
  mut state : MigrationState
}

///|
pub fn MigrationPlan::new(
  id : String,
  from_version : Int,
  to_version : Int,
  max_steps? : Int = 256,
) -> Result[MigrationPlan, ModbusError] {
  if id == "" || from_version < 0 || to_version <= from_version || max_steps < 1 {
    return Err(InvalidData)
  }
  Ok({
    id,
    from_version,
    to_version,
    steps: [],
    max_steps,
    state: MigrationPlanned,
  })
}

///|
pub fn MigrationPlan::id(self : MigrationPlan) -> String {
  self.id
}

///|
pub fn MigrationPlan::from_version(self : MigrationPlan) -> Int {
  self.from_version
}

///|
pub fn MigrationPlan::to_version(self : MigrationPlan) -> Int {
  self.to_version
}

///|
pub fn MigrationPlan::state(self : MigrationPlan) -> MigrationState {
  self.state
}

///|
pub fn MigrationPlan::step_count(self : MigrationPlan) -> Int {
  self.steps.length()
}

///|
pub fn MigrationPlan::add_step(
  self : MigrationPlan,
  step : MigrationStep,
) -> Result[Unit, ModbusError] {
  if self.state != MigrationPlanned || self.steps.length() >= self.max_steps {
    return Err(Busy)
  }
  for existing in self.steps {
    if existing.id() == step.id() || existing.order() == step.order() {
      return Err(InvalidData)
    }
  }
  self.steps.push(step)
  Ok(())
}

///|
fn MigrationPlan::ordered_steps(self : MigrationPlan) -> Array[MigrationStep] {
  let remaining = self.steps.copy()
  let result : Array[MigrationStep] = []
  while remaining.length() > 0 {
    let mut best = 0
    for i in 1..<remaining.length() {
      if remaining[i].order() < remaining[best].order() {
        best = i
      }
    }
    result.push(remaining.remove(best))
  }
  result
}

///|
/// Apply each step and return the changed snapshot.
pub fn MigrationPlan::apply(
  self : MigrationPlan,
  snapshot : MigrationSnapshot,
) -> Result[MigrationSnapshot, ModbusError] {
  if self.state != MigrationPlanned || snapshot.version() != self.from_version {
    return Err(Busy)
  }
  self.state = MigrationRunning
  for step in self.ordered_steps() {
    let result = match step.operation() {
      AddSetting | ReplaceSetting | ValidateSetting =>
        snapshot.put(step.key(), step.value())
      RemoveSetting =>
        match snapshot.remove(step.key()) {
          Ok(_) => Ok(())
          Err(error) => Err(error)
        }
      RenameSetting =>
        match snapshot.remove(step.key()) {
          Ok(old) => snapshot.put(step.value(), old)
          Err(error) => Err(error)
        }
    }
    match result {
      Err(error) => {
        self.state = MigrationFailed
        return Err(error)
      }
      Ok(_) => step.mark_applied()
    }
  }
  self.state = MigrationApplied
  Ok({
    version: self.to_version,
    entries: snapshot.entries,
    timestamp: snapshot.timestamp,
  })
}

///|
/// Roll back applied steps in reverse order where rollback values exist.
pub fn MigrationPlan::rollback(
  self : MigrationPlan,
  snapshot : MigrationSnapshot,
) -> Result[MigrationSnapshot, ModbusError] {
  if self.state != MigrationApplied {
    return Err(Busy)
  }
  let ordered = self.ordered_steps()
  let mut index = ordered.length() - 1
  while index >= 0 {
    let step = ordered[index]
    if step.applied() {
      match step.rollback_value() {
        Some(value) => ignore(snapshot.put(step.key(), value))
        None => ignore(snapshot.remove(step.key()))
      }
      step.mark_pending()
    }
    index -= 1
  }
  self.state = MigrationRolledBack
  Ok({
    version: self.from_version,
    entries: snapshot.entries,
    timestamp: snapshot.timestamp,
  })
}

///|
pub fn MigrationPlan::export_lines(self : MigrationPlan) -> Array[String] {
  let lines : Array[String] = []
  lines.push(
    "migration=" +
    self.id +
    " from=" +
    self.from_version.to_string() +
    " to=" +
    self.to_version.to_string() +
    " state=" +
    migration_state_name(self.state),
  )
  for step in self.steps {
    lines.push(
      "step=" +
      step.id() +
      " op=" +
      migration_operation_name(step.operation()) +
      " key=" +
      step.key() +
      " order=" +
      step.order().to_string() +
      " applied=" +
      step.applied().to_string(),
    )
  }
  lines
}

///|
pub fn migration_state_name(state : MigrationState) -> String {
  match state {
    MigrationPlanned => "planned"
    MigrationRunning => "running"
    MigrationApplied => "applied"
    MigrationRolledBack => "rolled-back"
    MigrationFailed => "failed"
  }
}
