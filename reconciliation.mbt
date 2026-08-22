///|
/// Difference class produced when comparing two device observations.
pub(all) enum ReconciliationKind {
  MissingPoint
  AddedPoint
  ValueChanged
  QualityChanged
  TimestampRegressed
  SnapshotComplete
} derive(Debug, Eq)

///|
/// One difference between an expected and observed snapshot.
pub(all) struct ReconciliationDiff {
  point_id : String
  kind : ReconciliationKind
  expected : Int?
  observed : Int?
  detail : String
}

///|
pub fn ReconciliationDiff::new(
  point_id : String,
  kind : ReconciliationKind,
  expected? : Int = 0,
  observed? : Int = 0,
  detail? : String = "",
) -> Result[ReconciliationDiff, ModbusError] {
  if point_id == "" {
    Err(InvalidData)
  } else {
    let selected_expected = if expected == 0 { None } else { Some(expected) }
    let selected_observed = if observed == 0 { None } else { Some(observed) }
    Ok({
      point_id,
      kind,
      expected: selected_expected,
      observed: selected_observed,
      detail,
    })
  }
}

///|
pub fn ReconciliationDiff::point_id(self : ReconciliationDiff) -> String {
  self.point_id
}

///|
pub fn ReconciliationDiff::kind(
  self : ReconciliationDiff,
) -> ReconciliationKind {
  self.kind
}

///|
pub fn ReconciliationDiff::expected(self : ReconciliationDiff) -> Int? {
  self.expected
}

///|
pub fn ReconciliationDiff::observed(self : ReconciliationDiff) -> Int? {
  self.observed
}

///|
pub fn ReconciliationDiff::detail(self : ReconciliationDiff) -> String {
  self.detail
}

///|
pub fn reconciliation_kind_name(kind : ReconciliationKind) -> String {
  match kind {
    MissingPoint => "missing"
    AddedPoint => "added"
    ValueChanged => "value-changed"
    QualityChanged => "quality-changed"
    TimestampRegressed => "timestamp-regressed"
    SnapshotComplete => "complete"
  }
}

///|
/// Compare point values and qualities in two snapshots.
pub fn reconcile_snapshots(
  expected : DeviceSnapshot,
  observed : DeviceSnapshot,
) -> Result[Array[ReconciliationDiff], ModbusError] {
  if expected.device_id() != observed.device_id() {
    return Err(UnitMismatch)
  }
  let result : Array[ReconciliationDiff] = []
  for value in expected.values {
    match observed.get(value.point_id()) {
      None => {
        let diff = match
          ReconciliationDiff::new(
            value.point_id(),
            MissingPoint,
            expected=value.value(),
            detail="not-observed",
          ) {
          Ok(item) => item
          Err(error) => return Err(error)
        }
        result.push(diff)
      }
      Some(other) => {
        if value.value() != other.value() {
          let diff = match
            ReconciliationDiff::new(
              value.point_id(),
              ValueChanged,
              expected=value.value(),
              observed=other.value(),
              detail="value-mismatch",
            ) {
            Ok(item) => item
            Err(error) => return Err(error)
          }
          result.push(diff)
        }
        if value.quality() != other.quality() {
          let diff = match
            ReconciliationDiff::new(
              value.point_id(),
              QualityChanged,
              detail="quality-mismatch",
            ) {
            Ok(item) => item
            Err(error) => return Err(error)
          }
          result.push(diff)
        }
      }
    }
  }
  for value in observed.values {
    match expected.get(value.point_id()) {
      None => {
        let diff = match
          ReconciliationDiff::new(
            value.point_id(),
            AddedPoint,
            observed=value.value(),
            detail="unexpected-point",
          ) {
          Ok(item) => item
          Err(error) => return Err(error)
        }
        result.push(diff)
      }
      Some(_) => ()
    }
  }
  if expected.complete() && observed.complete() && result.length() == 0 {
    let diff = match
      ReconciliationDiff::new(
        expected.device_id(),
        SnapshotComplete,
        detail="snapshots-equivalent",
      ) {
      Ok(item) => item
      Err(error) => return Err(error)
    }
    result.push(diff)
  }
  Ok(result)
}

///|
/// Accumulated reconciliation result for a device fleet.
pub(all) struct ReconciliationReport {
  device_id : String
  compared : Int
  differences : Int
  missing : Int
  added : Int
  changed : Int
  equivalent : Bool
}

///|
pub fn reconciliation_report(
  device_id : String,
  diffs : Array[ReconciliationDiff],
  compared : Int,
) -> Result[ReconciliationReport, ModbusError] {
  if device_id == "" || compared < 0 {
    return Err(InvalidData)
  }
  let mut missing = 0
  let mut added = 0
  let mut changed = 0
  for diff in diffs {
    match diff.kind() {
      MissingPoint => missing += 1
      AddedPoint => added += 1
      ValueChanged | QualityChanged | TimestampRegressed => changed += 1
      SnapshotComplete => ()
    }
  }
  Ok({
    device_id,
    compared,
    differences: diffs.length(),
    missing,
    added,
    changed,
    equivalent: diffs.length() == 0 ||
    (diffs.length() == 1 && diffs[0].kind() == SnapshotComplete),
  })
}

///|
pub fn ReconciliationReport::device_id(self : ReconciliationReport) -> String {
  self.device_id
}

///|
pub fn ReconciliationReport::compared(self : ReconciliationReport) -> Int {
  self.compared
}

///|
pub fn ReconciliationReport::differences(self : ReconciliationReport) -> Int {
  self.differences
}

///|
pub fn ReconciliationReport::missing(self : ReconciliationReport) -> Int {
  self.missing
}

///|
pub fn ReconciliationReport::added(self : ReconciliationReport) -> Int {
  self.added
}

///|
pub fn ReconciliationReport::changed(self : ReconciliationReport) -> Int {
  self.changed
}

///|
pub fn ReconciliationReport::equivalent(self : ReconciliationReport) -> Bool {
  self.equivalent
}
