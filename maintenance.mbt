///|
/// Type of maintenance activity tracked for a field device.
pub(all) enum MaintenanceKind {
  Inspection
  Calibration
  Cleaning
  FirmwareUpdate
  CableReplacement
  PreventiveService
  CorrectiveRepair
} derive(Debug, Eq)

///|
/// State of a maintenance work order.
pub(all) enum WorkOrderState {
  Planned
  Assigned
  InProgress
  Blocked
  Completed
  Cancelled
} derive(Debug, Eq)

///|
/// Priority assigned by an operator or by an automated due-date rule.
pub(all) enum MaintenancePriority {
  Routine
  Important
  Urgent
  Critical
} derive(Debug, Eq)

///|
/// A repeatable service plan for one device or profile point.
pub(all) struct ServicePlan {
  id : String
  asset_id : String
  title : String
  kind : MaintenanceKind
  interval : Int
  grace : Int
  estimated_minutes : Int
  mut enabled : Bool
  mut last_completed : Int?
  owner : String
}

///|
pub fn ServicePlan::new(
  id : String,
  asset_id : String,
  title : String,
  kind : MaintenanceKind,
  interval : Int,
  grace? : Int = 0,
  estimated_minutes? : Int = 30,
  owner? : String = "",
) -> Result[ServicePlan, ModbusError] {
  if id == "" || asset_id == "" || title == "" {
    return Err(InvalidData)
  }
  if interval < 1 || grace < 0 || estimated_minutes < 1 {
    return Err(InvalidData)
  }
  Ok({
    id,
    asset_id,
    title,
    kind,
    interval,
    grace,
    estimated_minutes,
    enabled: true,
    last_completed: None,
    owner,
  })
}

///|
pub fn ServicePlan::id(self : ServicePlan) -> String {
  self.id
}

///|
pub fn ServicePlan::asset_id(self : ServicePlan) -> String {
  self.asset_id
}

///|
pub fn ServicePlan::title(self : ServicePlan) -> String {
  self.title
}

///|
pub fn ServicePlan::kind(self : ServicePlan) -> MaintenanceKind {
  self.kind
}

///|
pub fn ServicePlan::interval(self : ServicePlan) -> Int {
  self.interval
}

///|
pub fn ServicePlan::grace(self : ServicePlan) -> Int {
  self.grace
}

///|
pub fn ServicePlan::estimated_minutes(self : ServicePlan) -> Int {
  self.estimated_minutes
}

///|
pub fn ServicePlan::owner(self : ServicePlan) -> String {
  self.owner
}

///|
pub fn ServicePlan::enabled(self : ServicePlan) -> Bool {
  self.enabled
}

///|
pub fn ServicePlan::last_completed(self : ServicePlan) -> Int? {
  self.last_completed
}

///|
pub fn ServicePlan::set_enabled(self : ServicePlan, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
pub fn ServicePlan::due_at(self : ServicePlan) -> Int? {
  match self.last_completed {
    Some(timestamp) => Some(timestamp + self.interval)
    None => None
  }
}

///|
pub fn ServicePlan::mark_completed(
  self : ServicePlan,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < 0 {
    return Err(InvalidData)
  }
  match self.last_completed {
    Some(previous) => if timestamp < previous { return Err(InvalidData) }
    None => ()
  }
  self.last_completed = Some(timestamp)
  Ok(())
}

///|
pub fn ServicePlan::is_due(
  self : ServicePlan,
  now : Int,
) -> Result[Bool, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  if !self.enabled {
    return Ok(false)
  }
  match self.due_at() {
    Some(due) => Ok(now >= due)
    None => Ok(true)
  }
}

///|
pub fn ServicePlan::is_overdue(
  self : ServicePlan,
  now : Int,
) -> Result[Bool, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  if !self.enabled {
    return Ok(false)
  }
  match self.due_at() {
    Some(due) => Ok(now > due + self.grace)
    None => Ok(false)
  }
}

///|
pub fn ServicePlan::priority(
  self : ServicePlan,
  now : Int,
) -> Result[MaintenancePriority, ModbusError] {
  match self.is_overdue(now) {
    Err(error) => Err(error)
    Ok(true) => Ok(Critical)
    Ok(false) =>
      match self.is_due(now) {
        Err(error) => Err(error)
        Ok(true) => Ok(Important)
        Ok(false) => Ok(Routine)
      }
  }
}

///|
pub fn maintenance_kind_name(kind : MaintenanceKind) -> String {
  match kind {
    Inspection => "inspection"
    Calibration => "calibration"
    Cleaning => "cleaning"
    FirmwareUpdate => "firmware-update"
    CableReplacement => "cable-replacement"
    PreventiveService => "preventive-service"
    CorrectiveRepair => "corrective-repair"
  }
}

///|
pub fn maintenance_priority_name(priority : MaintenancePriority) -> String {
  match priority {
    Routine => "routine"
    Important => "important"
    Urgent => "urgent"
    Critical => "critical"
  }
}

///|
pub fn work_order_state_name(state : WorkOrderState) -> String {
  match state {
    Planned => "planned"
    Assigned => "assigned"
    InProgress => "in-progress"
    Blocked => "blocked"
    Completed => "completed"
    Cancelled => "cancelled"
  }
}

///|
/// A historical service record including measurements and the operator note.
pub(all) struct ServiceRecord {
  id : String
  plan_id : String
  asset_id : String
  started_at : Int
  finished_at : Int
  technician : String
  result : String
  readings : Array[Int]
  parts : Array[String]
}

///|
pub fn ServiceRecord::new(
  id : String,
  plan_id : String,
  asset_id : String,
  started_at : Int,
  finished_at : Int,
  technician : String,
  result : String,
) -> Result[ServiceRecord, ModbusError] {
  if id == "" ||
    plan_id == "" ||
    asset_id == "" ||
    technician == "" ||
    result == "" {
    return Err(InvalidData)
  }
  if started_at < 0 || finished_at < started_at {
    return Err(InvalidData)
  }
  Ok({
    id,
    plan_id,
    asset_id,
    started_at,
    finished_at,
    technician,
    result,
    readings: [],
    parts: [],
  })
}

///|
pub fn ServiceRecord::id(self : ServiceRecord) -> String {
  self.id
}

///|
pub fn ServiceRecord::plan_id(self : ServiceRecord) -> String {
  self.plan_id
}

///|
pub fn ServiceRecord::asset_id(self : ServiceRecord) -> String {
  self.asset_id
}

///|
pub fn ServiceRecord::started_at(self : ServiceRecord) -> Int {
  self.started_at
}

///|
pub fn ServiceRecord::finished_at(self : ServiceRecord) -> Int {
  self.finished_at
}

///|
pub fn ServiceRecord::technician(self : ServiceRecord) -> String {
  self.technician
}

///|
pub fn ServiceRecord::result(self : ServiceRecord) -> String {
  self.result
}

///|
pub fn ServiceRecord::duration(self : ServiceRecord) -> Int {
  self.finished_at - self.started_at
}

///|
pub fn ServiceRecord::add_reading(self : ServiceRecord, reading : Int) -> Unit {
  self.readings.push(reading)
}

///|
pub fn ServiceRecord::add_part(
  self : ServiceRecord,
  part : String,
) -> Result[Unit, ModbusError] {
  if part == "" {
    Err(InvalidData)
  } else {
    self.parts.push(part)
    Ok(())
  }
}

///|
pub fn ServiceRecord::reading_count(self : ServiceRecord) -> Int {
  self.readings.length()
}

///|
pub fn ServiceRecord::part_count(self : ServiceRecord) -> Int {
  self.parts.length()
}

///|
pub fn ServiceRecord::average_reading(
  self : ServiceRecord,
) -> Result[Int, ModbusError] {
  if self.readings.length() == 0 {
    return Err(Incomplete)
  }
  let mut sum = 0
  for value in self.readings {
    sum += value
  }
  Ok(sum / self.readings.length())
}

///|
/// An actionable unit of work generated from a service plan or alarm.
pub(all) struct MaintenanceWorkOrder {
  id : String
  asset_id : String
  plan_id : String?
  title : String
  priority : MaintenancePriority
  mut state : WorkOrderState
  created_at : Int
  due_at : Int
  mut assigned_to : String?
  mut started_at : Int?
  mut finished_at : Int?
  mut note : String
}

///|
pub fn MaintenanceWorkOrder::new(
  id : String,
  asset_id : String,
  title : String,
  priority : MaintenancePriority,
  created_at : Int,
  due_at : Int,
  plan_id? : String = "",
) -> Result[MaintenanceWorkOrder, ModbusError] {
  if id == "" ||
    asset_id == "" ||
    title == "" ||
    created_at < 0 ||
    due_at < created_at {
    return Err(InvalidData)
  }
  let selected_plan = if plan_id == "" { None } else { Some(plan_id) }
  Ok({
    id,
    asset_id,
    plan_id: selected_plan,
    title,
    priority,
    state: Planned,
    created_at,
    due_at,
    assigned_to: None,
    started_at: None,
    finished_at: None,
    note: "",
  })
}

///|
pub fn MaintenanceWorkOrder::id(self : MaintenanceWorkOrder) -> String {
  self.id
}

///|
pub fn MaintenanceWorkOrder::asset_id(self : MaintenanceWorkOrder) -> String {
  self.asset_id
}

///|
pub fn MaintenanceWorkOrder::plan_id(self : MaintenanceWorkOrder) -> String? {
  self.plan_id
}

///|
pub fn MaintenanceWorkOrder::title(self : MaintenanceWorkOrder) -> String {
  self.title
}

///|
pub fn MaintenanceWorkOrder::priority(
  self : MaintenanceWorkOrder,
) -> MaintenancePriority {
  self.priority
}

///|
pub fn MaintenanceWorkOrder::state(
  self : MaintenanceWorkOrder,
) -> WorkOrderState {
  self.state
}

///|
pub fn MaintenanceWorkOrder::created_at(self : MaintenanceWorkOrder) -> Int {
  self.created_at
}

///|
pub fn MaintenanceWorkOrder::due_at(self : MaintenanceWorkOrder) -> Int {
  self.due_at
}

///|
pub fn MaintenanceWorkOrder::assigned_to(
  self : MaintenanceWorkOrder,
) -> String? {
  self.assigned_to
}

///|
pub fn MaintenanceWorkOrder::note(self : MaintenanceWorkOrder) -> String {
  self.note
}

///|
pub fn MaintenanceWorkOrder::assign(
  self : MaintenanceWorkOrder,
  technician : String,
) -> Result[Unit, ModbusError] {
  if technician == "" || self.state == Completed || self.state == Cancelled {
    return Err(Busy)
  }
  self.assigned_to = Some(technician)
  self.state = Assigned
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::start(
  self : MaintenanceWorkOrder,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if timestamp < self.created_at ||
    self.state == Completed ||
    self.state == Cancelled {
    return Err(InvalidData)
  }
  match self.assigned_to {
    None => return Err(Busy)
    Some(_) => ()
  }
  self.started_at = Some(timestamp)
  self.state = InProgress
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::block(
  self : MaintenanceWorkOrder,
  note : String,
) -> Result[Unit, ModbusError] {
  if note == "" || self.state == Completed || self.state == Cancelled {
    return Err(InvalidData)
  }
  self.note = note
  self.state = Blocked
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::continue_work(
  self : MaintenanceWorkOrder,
) -> Result[Unit, ModbusError] {
  if self.state != Blocked {
    return Err(Busy)
  }
  self.state = match self.assigned_to {
    Some(_) => InProgress
    None => Planned
  }
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::complete(
  self : MaintenanceWorkOrder,
  timestamp : Int,
  note? : String = "",
) -> Result[Unit, ModbusError] {
  if timestamp < self.created_at || self.state == Cancelled {
    return Err(InvalidData)
  }
  match self.started_at {
    Some(started) => if timestamp < started { return Err(InvalidData) }
    None => return Err(Busy)
  }
  self.finished_at = Some(timestamp)
  if note != "" {
    self.note = note
  }
  self.state = Completed
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::cancel(
  self : MaintenanceWorkOrder,
  reason : String,
) -> Result[Unit, ModbusError] {
  if reason == "" || self.state == Completed {
    return Err(Busy)
  }
  self.note = reason
  self.state = Cancelled
  Ok(())
}

///|
pub fn MaintenanceWorkOrder::is_due(
  self : MaintenanceWorkOrder,
  now : Int,
) -> Bool {
  now >= self.due_at && self.state != Completed && self.state != Cancelled
}

///|
pub fn MaintenanceWorkOrder::is_overdue(
  self : MaintenanceWorkOrder,
  now : Int,
) -> Bool {
  now > self.due_at && self.state != Completed && self.state != Cancelled
}

///|
pub fn MaintenanceWorkOrder::duration(self : MaintenanceWorkOrder) -> Int? {
  match (self.started_at, self.finished_at) {
    (Some(started), Some(finished)) => Some(finished - started)
    _ => None
  }
}

///|
/// Plan and audit maintenance across multiple devices.
pub(all) struct MaintenancePlanner {
  plans : Array[ServicePlan]
  records : Array[ServiceRecord]
  work_orders : Array[MaintenanceWorkOrder]
  max_records : Int
  max_orders : Int
}

///|
pub fn MaintenancePlanner::new(
  max_records? : Int = 4096,
  max_orders? : Int = 4096,
) -> Result[MaintenancePlanner, ModbusError] {
  if max_records < 1 || max_orders < 1 {
    Err(InvalidData)
  } else {
    Ok({ plans: [], records: [], work_orders: [], max_records, max_orders })
  }
}

///|
pub fn MaintenancePlanner::plan_count(self : MaintenancePlanner) -> Int {
  self.plans.length()
}

///|
pub fn MaintenancePlanner::record_count(self : MaintenancePlanner) -> Int {
  self.records.length()
}

///|
pub fn MaintenancePlanner::work_order_count(self : MaintenancePlanner) -> Int {
  self.work_orders.length()
}

///|
pub fn MaintenancePlanner::add_plan(
  self : MaintenancePlanner,
  plan : ServicePlan,
) -> Result[Unit, ModbusError] {
  for existing in self.plans {
    if existing.id() == plan.id() {
      return Err(InvalidData)
    }
  }
  self.plans.push(plan)
  Ok(())
}

///|
pub fn MaintenancePlanner::plan(
  self : MaintenancePlanner,
  id : String,
) -> ServicePlan? {
  for plan in self.plans {
    if plan.id() == id {
      return Some(plan)
    }
  }
  None
}

///|
pub fn MaintenancePlanner::add_record(
  self : MaintenancePlanner,
  record : ServiceRecord,
) -> Result[Unit, ModbusError] {
  if self.records.length() >= self.max_records {
    return Err(CapacityExceeded)
  }
  self.records.push(record)
  Ok(())
}

///|
pub fn MaintenancePlanner::add_work_order(
  self : MaintenancePlanner,
  order : MaintenanceWorkOrder,
) -> Result[Unit, ModbusError] {
  if self.work_orders.length() >= self.max_orders {
    return Err(CapacityExceeded)
  }
  for existing in self.work_orders {
    if existing.id() == order.id() {
      return Err(InvalidData)
    }
  }
  self.work_orders.push(order)
  Ok(())
}

///|
pub fn MaintenancePlanner::work_order(
  self : MaintenancePlanner,
  id : String,
) -> MaintenanceWorkOrder? {
  for order in self.work_orders {
    if order.id() == id {
      return Some(order)
    }
  }
  None
}

///|
/// Generate due work orders for plans that have not been scheduled at `now`.
pub fn MaintenancePlanner::generate_due(
  self : MaintenancePlanner,
  now : Int,
) -> Result[Int, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let mut created = 0
  for plan in self.plans {
    match plan.is_due(now) {
      Err(error) => return Err(error)
      Ok(false) => ()
      Ok(true) => {
        let mut already_open = false
        for order in self.work_orders {
          match order.plan_id() {
            Some(plan_id) =>
              if plan_id == plan.id() &&
                order.state() != Completed &&
                order.state() != Cancelled {
                already_open = true
              }
            None => ()
          }
        }
        if !already_open &&
          self.work_orders.length() + created < self.max_orders {
          let priority = match plan.priority(now) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          let order_id = "auto-" + plan.id() + "-" + now.to_string()
          let order = match
            MaintenanceWorkOrder::new(
              order_id,
              plan.asset_id(),
              plan.title(),
              priority,
              now,
              now,
              plan_id=plan.id(),
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          self.work_orders.push(order)
          created += 1
        }
      }
    }
  }
  Ok(created)
}

///|
/// Complete a linked order and update the corresponding service plan.
pub fn MaintenancePlanner::complete_order(
  self : MaintenancePlanner,
  order_id : String,
  timestamp : Int,
  note? : String = "",
) -> Result[Unit, ModbusError] {
  for order in self.work_orders {
    if order.id() == order_id {
      match order.plan_id() {
        Some(plan_id) =>
          for plan in self.plans {
            if plan.id() == plan_id {
              ignore(plan.mark_completed(timestamp))
            }
          }
        None => ()
      }
      return order.complete(timestamp, note~)
    }
  }
  Err(InvalidData)
}

///|
/// Return plans due or overdue at a timestamp.
pub fn MaintenancePlanner::due_plans(
  self : MaintenancePlanner,
  now : Int,
) -> Result[Array[String], ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for plan in self.plans {
    match plan.is_due(now) {
      Ok(true) => result.push(plan.id())
      Err(error) => return Err(error)
      _ => ()
    }
  }
  Ok(result)
}

///|
/// Return the IDs of open work orders, optionally limited to overdue work.
pub fn MaintenancePlanner::open_orders(
  self : MaintenancePlanner,
  now : Int,
  overdue_only? : Bool = false,
) -> Result[Array[String], ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for order in self.work_orders {
    if order.state() != Completed && order.state() != Cancelled {
      if !overdue_only || order.is_overdue(now) {
        result.push(order.id())
      }
    }
  }
  Ok(result)
}

///|
/// Count service records for an asset within a time range.
pub fn MaintenancePlanner::history_count(
  self : MaintenancePlanner,
  asset_id : String,
  start : Int,
  end : Int,
) -> Result[Int, ModbusError] {
  if asset_id == "" || start < 0 || end < start {
    return Err(InvalidData)
  }
  let mut count = 0
  for record in self.records {
    if record.asset_id() == asset_id &&
      record.finished_at() >= start &&
      record.finished_at() <= end {
      count += 1
    }
  }
  Ok(count)
}

///|
/// Summary for maintenance dashboards and export jobs.
pub(all) struct MaintenanceSummary {
  plans : Int
  due : Int
  overdue : Int
  completed : Int
  open : Int
  records : Int
}

///|
pub fn MaintenancePlanner::summary(
  self : MaintenancePlanner,
  now : Int,
) -> Result[MaintenanceSummary, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let mut due = 0
  for plan in self.plans {
    match plan.is_due(now) {
      Ok(true) => due += 1
      _ => ()
    }
  }
  let mut overdue = 0
  let mut completed = 0
  let mut open = 0
  for order in self.work_orders {
    match order.state() {
      Completed => completed += 1
      Cancelled => ()
      _ => {
        open += 1
        if order.is_overdue(now) {
          overdue += 1
        }
      }
    }
  }
  Ok({
    plans: self.plans.length(),
    due,
    overdue,
    completed,
    open,
    records: self.records.length(),
  })
}

///|
pub fn MaintenanceSummary::plans(self : MaintenanceSummary) -> Int {
  self.plans
}

///|
pub fn MaintenanceSummary::due(self : MaintenanceSummary) -> Int {
  self.due
}

///|
pub fn MaintenanceSummary::overdue(self : MaintenanceSummary) -> Int {
  self.overdue
}

///|
pub fn MaintenanceSummary::completed(self : MaintenanceSummary) -> Int {
  self.completed
}

///|
pub fn MaintenanceSummary::open(self : MaintenanceSummary) -> Int {
  self.open
}

///|
pub fn MaintenanceSummary::records(self : MaintenanceSummary) -> Int {
  self.records
}

///|
pub fn MaintenanceSummary::summary(self : MaintenanceSummary) -> String {
  "plans=" +
  self.plans.to_string() +
  " due=" +
  self.due.to_string() +
  " overdue=" +
  self.overdue.to_string() +
  " open=" +
  self.open.to_string() +
  " completed=" +
  self.completed.to_string() +
  " records=" +
  self.records.to_string()
}
