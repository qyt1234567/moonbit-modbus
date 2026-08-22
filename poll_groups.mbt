///|
/// Address space selected by a polling point.
pub(all) enum PollArea {
  PollCoils
  PollDiscreteInputs
  PollHoldingRegisters
  PollInputRegisters
} derive(Debug, Eq)

///|
/// A point requested by a periodic acquisition job.
pub(all) struct PollPoint {
  id : String
  device_id : String
  unit_id : Byte
  area : PollArea
  address : UInt16
  quantity : Int
  period : Int
  priority : Int
  mut enabled : Bool
}

///|
pub fn PollPoint::new(
  id : String,
  device_id : String,
  unit_id : Byte,
  area : PollArea,
  address : UInt16,
  quantity : Int,
  period : Int,
  priority? : Int = 0,
) -> Result[PollPoint, ModbusError] {
  if id == "" ||
    device_id == "" ||
    !is_valid_unit_id(unit_id) ||
    quantity < 1 ||
    period < 1 ||
    priority < 0 {
    return Err(InvalidData)
  }
  let limit = match area {
    PollCoils | PollDiscreteInputs => 2000
    PollHoldingRegisters | PollInputRegisters => 125
  }
  if quantity > limit || !valid_address_range(address, quantity) {
    return Err(InvalidAddress)
  }
  Ok({
    id,
    device_id,
    unit_id,
    area,
    address,
    quantity,
    period,
    priority,
    enabled: true,
  })
}

///|
pub fn PollPoint::id(self : PollPoint) -> String {
  self.id
}

///|
pub fn PollPoint::device_id(self : PollPoint) -> String {
  self.device_id
}

///|
pub fn PollPoint::unit_id(self : PollPoint) -> Byte {
  self.unit_id
}

///|
pub fn PollPoint::area(self : PollPoint) -> PollArea {
  self.area
}

///|
pub fn PollPoint::address(self : PollPoint) -> UInt16 {
  self.address
}

///|
pub fn PollPoint::quantity(self : PollPoint) -> Int {
  self.quantity
}

///|
pub fn PollPoint::period(self : PollPoint) -> Int {
  self.period
}

///|
pub fn PollPoint::priority(self : PollPoint) -> Int {
  self.priority
}

///|
pub fn PollPoint::enabled(self : PollPoint) -> Bool {
  self.enabled
}

///|
pub fn PollPoint::set_enabled(self : PollPoint, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
pub fn PollPoint::end_exclusive(self : PollPoint) -> Int {
  self.address.to_int() + self.quantity
}

///|
pub fn PollPoint::overlaps(self : PollPoint, other : PollPoint) -> Bool {
  self.device_id == other.device_id &&
  self.unit_id == other.unit_id &&
  self.area == other.area &&
  self.address.to_int() < other.end_exclusive() &&
  other.address.to_int() < self.end_exclusive()
}

///|
pub fn poll_area_function(area : PollArea) -> Byte {
  match area {
    PollCoils => 1
    PollDiscreteInputs => 2
    PollHoldingRegisters => 3
    PollInputRegisters => 4
  }
}

///|
pub fn poll_area_name(area : PollArea) -> String {
  match area {
    PollCoils => "coils"
    PollDiscreteInputs => "discrete-inputs"
    PollHoldingRegisters => "holding-registers"
    PollInputRegisters => "input-registers"
  }
}

///|
/// A contiguous request made from one or more polling points.
pub(all) struct PollRequestGroup {
  id : String
  device_id : String
  unit_id : Byte
  area : PollArea
  address : UInt16
  mut quantity : Int
  points : Array[String]
  mut period : Int
  mut priority : Int
}

///|
pub fn PollRequestGroup::new(
  id : String,
  first : PollPoint,
) -> PollRequestGroup {
  {
    id,
    device_id: first.device_id(),
    unit_id: first.unit_id(),
    area: first.area(),
    address: first.address(),
    quantity: first.quantity(),
    points: [first.id()],
    period: first.period(),
    priority: first.priority(),
  }
}

///|
pub fn PollRequestGroup::id(self : PollRequestGroup) -> String {
  self.id
}

///|
pub fn PollRequestGroup::device_id(self : PollRequestGroup) -> String {
  self.device_id
}

///|
pub fn PollRequestGroup::unit_id(self : PollRequestGroup) -> Byte {
  self.unit_id
}

///|
pub fn PollRequestGroup::area(self : PollRequestGroup) -> PollArea {
  self.area
}

///|
pub fn PollRequestGroup::address(self : PollRequestGroup) -> UInt16 {
  self.address
}

///|
pub fn PollRequestGroup::quantity(self : PollRequestGroup) -> Int {
  self.quantity
}

///|
pub fn PollRequestGroup::period(self : PollRequestGroup) -> Int {
  self.period
}

///|
pub fn PollRequestGroup::priority(self : PollRequestGroup) -> Int {
  self.priority
}

///|
pub fn PollRequestGroup::point_count(self : PollRequestGroup) -> Int {
  self.points.length()
}

///|
pub fn PollRequestGroup::points(self : PollRequestGroup) -> Array[String] {
  self.points
}

///|
pub fn PollRequestGroup::end_exclusive(self : PollRequestGroup) -> Int {
  self.address.to_int() + self.quantity
}

///|
pub fn PollRequestGroup::can_merge(
  self : PollRequestGroup,
  point : PollPoint,
  gap : Int,
) -> Bool {
  if gap < 0 ||
    point.device_id() != self.device_id ||
    point.unit_id() != self.unit_id ||
    point.area() != self.area {
    return false
  }
  if point.address().to_int() < self.address.to_int() {
    return false
  }
  point.address().to_int() <= self.end_exclusive() + gap &&
  point.end_exclusive() <= 65536
}

///|
pub fn PollRequestGroup::merge(
  self : PollRequestGroup,
  point : PollPoint,
) -> Result[Unit, ModbusError] {
  if !self.can_merge(point, 0) {
    return Err(UnitMismatch)
  }
  let end = if point.end_exclusive() > self.end_exclusive() {
    point.end_exclusive()
  } else {
    self.end_exclusive()
  }
  self.quantity = end - self.address.to_int()
  self.points.push(point.id())
  if point.period() < self.period {
    self.period = point.period()
  }
  if point.priority() > self.priority {
    self.priority = point.priority()
  }
  Ok(())
}

///|
/// Build the request frame for a contiguous poll group.
pub fn PollRequestGroup::request(
  self : PollRequestGroup,
) -> Result[Frame, ModbusError] {
  match self.area {
    PollCoils =>
      read_coils(self.unit_id, self.address, self.quantity.to_uint16())
    PollDiscreteInputs =>
      read_discrete_inputs(
        self.unit_id,
        self.address,
        self.quantity.to_uint16(),
      )
    PollHoldingRegisters =>
      read_holding_registers(
        self.unit_id,
        self.address,
        self.quantity.to_uint16(),
      )
    PollInputRegisters =>
      read_input_registers(
        self.unit_id,
        self.address,
        self.quantity.to_uint16(),
      )
  }
}

///|
pub fn PollRequestGroup::summary(self : PollRequestGroup) -> String {
  self.id +
  " " +
  poll_area_name(self.area) +
  " " +
  self.address.to_int().to_string() +
  "+" +
  self.quantity.to_string() +
  " points=" +
  self.points.length().to_string()
}

///|
/// A complete plan generated from point definitions.
pub(all) struct PollGroupPlan {
  points : Array[PollPoint]
  groups : Array[PollRequestGroup]
  max_groups : Int
  merge_gap : Int
  mut revision : Int
}

///|
pub fn PollGroupPlan::new(
  max_groups? : Int = 2048,
  merge_gap? : Int = 0,
) -> Result[PollGroupPlan, ModbusError] {
  if max_groups < 1 || merge_gap < 0 {
    Err(InvalidData)
  } else {
    Ok({ points: [], groups: [], max_groups, merge_gap, revision: 0 })
  }
}

///|
pub fn PollGroupPlan::point_count(self : PollGroupPlan) -> Int {
  self.points.length()
}

///|
pub fn PollGroupPlan::group_count(self : PollGroupPlan) -> Int {
  self.groups.length()
}

///|
pub fn PollGroupPlan::revision(self : PollGroupPlan) -> Int {
  self.revision
}

///|
pub fn PollGroupPlan::groups(self : PollGroupPlan) -> Array[PollRequestGroup] {
  self.groups
}

///|
pub fn PollGroupPlan::points(self : PollGroupPlan) -> Array[PollPoint] {
  self.points
}

///|
pub fn PollGroupPlan::add_point(
  self : PollGroupPlan,
  point : PollPoint,
) -> Result[Unit, ModbusError] {
  for existing in self.points {
    if existing.id() == point.id() {
      return Err(InvalidData)
    }
  }
  self.points.push(point)
  self.rebuild()
  Ok(())
}

///|
pub fn PollGroupPlan::remove_point(
  self : PollGroupPlan,
  id : String,
) -> Result[PollPoint, ModbusError] {
  let mut index = -1
  for i in 0..<self.points.length() {
    if self.points[i].id() == id {
      index = i
      break
    }
  }
  if index < 0 {
    return Err(InvalidData)
  }
  let removed = self.points.remove(index)
  self.rebuild()
  Ok(removed)
}

///|
/// Rebuild groups using a stable address order and contiguous coalescing.
pub fn PollGroupPlan::rebuild(self : PollGroupPlan) -> Unit {
  self.groups.clear()
  let pending = poll_sorted_points(self.points)
  for point in pending {
    if !point.enabled() {
      continue
    }
    let mut merged = false
    for group in self.groups {
      if group.can_merge(point, self.merge_gap) {
        ignore(group.merge(point))
        merged = true
        break
      }
    }
    if !merged {
      if self.groups.length() < self.max_groups {
        let group_id = "poll-" + self.groups.length().to_string()
        self.groups.push(PollRequestGroup::new(group_id, point))
      }
    }
  }
  self.revision += 1
}

///|
fn poll_sorted_points(points : Array[PollPoint]) -> Array[PollPoint] {
  let remaining = points.copy()
  let result : Array[PollPoint] = []
  while remaining.length() > 0 {
    let mut best = 0
    for i in 1..<remaining.length() {
      if poll_point_order(remaining[i], remaining[best]) < 0 {
        best = i
      }
    }
    result.push(remaining.remove(best))
  }
  result
}

///|
fn poll_point_order(left : PollPoint, right : PollPoint) -> Int {
  if left.device_id() < right.device_id() {
    return -1
  }
  if left.device_id() > right.device_id() {
    return 1
  }
  if left.unit_id() < right.unit_id() {
    return -1
  }
  if left.unit_id() > right.unit_id() {
    return 1
  }
  if poll_area_function(left.area()) < poll_area_function(right.area()) {
    return -1
  }
  if poll_area_function(left.area()) > poll_area_function(right.area()) {
    return 1
  }
  if left.address() < right.address() {
    -1
  } else if left.address() > right.address() {
    1
  } else {
    0
  }
}

///|
pub fn PollGroupPlan::request_for(
  self : PollGroupPlan,
  group_id : String,
) -> Result[Frame, ModbusError] {
  for group in self.groups {
    if group.id() == group_id {
      return group.request()
    }
  }
  Err(InvalidData)
}

///|
pub fn PollGroupPlan::groups_for(
  self : PollGroupPlan,
  device_id : String,
) -> Array[PollRequestGroup] {
  let result : Array[PollRequestGroup] = []
  for group in self.groups {
    if group.device_id() == device_id {
      result.push(group)
    }
  }
  result
}

///|
pub fn PollGroupPlan::due_groups(
  self : PollGroupPlan,
  now : Int,
  last_run : Array[(String, Int)],
) -> Result[Array[String], ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for group in self.groups {
    let mut previous = 0
    for item in last_run {
      if item.0 == group.id() {
        previous = item.1
      }
    }
    if previous == 0 || now - previous >= group.period() {
      result.push(group.id())
    }
  }
  Ok(result)
}

///|
pub fn PollGroupPlan::validate(self : PollGroupPlan) -> Array[ModbusError] {
  let result : Array[ModbusError] = []
  for point in self.points {
    if !point.enabled() {
      continue
    }
    if point.quantity() < 1 {
      result.push(InvalidQuantity)
    }
    if !valid_address_range(point.address(), point.quantity()) {
      result.push(InvalidAddress)
    }
  }
  for i in 0..<self.groups.length() {
    if self.groups[i].quantity() > 125 &&
      self.groups[i].area() != PollCoils &&
      self.groups[i].area() != PollDiscreteInputs {
      result.push(InvalidQuantity)
    }
  }
  result
}

///|
/// A budget for limiting requests emitted in one scheduler cycle.
pub(all) struct PollBudget {
  max_requests : Int
  max_registers : Int
  mut requests : Int
  mut registers : Int
  mut rejected : Int
}

///|
pub fn PollBudget::new(
  max_requests : Int,
  max_registers : Int,
) -> Result[PollBudget, ModbusError] {
  if max_requests < 1 || max_registers < 1 {
    Err(InvalidData)
  } else {
    Ok({ max_requests, max_registers, requests: 0, registers: 0, rejected: 0 })
  }
}

///|
pub fn PollBudget::max_requests(self : PollBudget) -> Int {
  self.max_requests
}

///|
pub fn PollBudget::max_registers(self : PollBudget) -> Int {
  self.max_registers
}

///|
pub fn PollBudget::requests(self : PollBudget) -> Int {
  self.requests
}

///|
pub fn PollBudget::registers(self : PollBudget) -> Int {
  self.registers
}

///|
pub fn PollBudget::rejected(self : PollBudget) -> Int {
  self.rejected
}

///|
pub fn PollBudget::accept(self : PollBudget, group : PollRequestGroup) -> Bool {
  let amount = if group.area() == PollCoils ||
    group.area() == PollDiscreteInputs {
    (group.quantity() + 15) / 16
  } else {
    group.quantity()
  }
  if self.requests >= self.max_requests ||
    self.registers + amount > self.max_registers {
    self.rejected += 1
    false
  } else {
    self.requests += 1
    self.registers += amount
    true
  }
}

///|
pub fn PollBudget::reset(self : PollBudget) -> Unit {
  self.requests = 0
  self.registers = 0
  self.rejected = 0
}

///|
pub fn PollBudget::remaining_requests(self : PollBudget) -> Int {
  self.max_requests - self.requests
}

///|
pub fn PollBudget::remaining_registers(self : PollBudget) -> Int {
  self.max_registers - self.registers
}

///|
/// Produce a budgeted batch while preserving group priority order.
pub fn PollGroupPlan::budgeted(
  self : PollGroupPlan,
  budget : PollBudget,
) -> Array[PollRequestGroup] {
  let ordered = poll_sorted_groups(self.groups)
  let result : Array[PollRequestGroup] = []
  for group in ordered {
    if budget.accept(group) {
      result.push(group)
    }
  }
  result
}

///|
fn poll_sorted_groups(
  groups : Array[PollRequestGroup],
) -> Array[PollRequestGroup] {
  let remaining = groups.copy()
  let result : Array[PollRequestGroup] = []
  while remaining.length() > 0 {
    let mut best = 0
    for i in 1..<remaining.length() {
      if remaining[i].priority() > remaining[best].priority() {
        best = i
      }
    }
    result.push(remaining.remove(best))
  }
  result
}

///|
/// A plan statistic used to tune address maps and transport budgets.
pub(all) struct PollPlanStats {
  points : Int
  enabled_points : Int
  groups : Int
  merged_points : Int
  estimated_registers : Int
  highest_priority : Int
}

///|
pub fn PollGroupPlan::stats(self : PollGroupPlan) -> PollPlanStats {
  let mut enabled = 0
  let mut highest = 0
  for point in self.points {
    if point.enabled() {
      enabled += 1
    }
    if point.priority() > highest {
      highest = point.priority()
    }
  }
  let mut registers = 0
  for group in self.groups {
    registers += group.quantity()
  }
  {
    points: self.points.length(),
    enabled_points: enabled,
    groups: self.groups.length(),
    merged_points: enabled - self.groups.length(),
    estimated_registers: registers,
    highest_priority: highest,
  }
}

///|
pub fn PollPlanStats::points(self : PollPlanStats) -> Int {
  self.points
}

///|
pub fn PollPlanStats::enabled_points(self : PollPlanStats) -> Int {
  self.enabled_points
}

///|
pub fn PollPlanStats::groups(self : PollPlanStats) -> Int {
  self.groups
}

///|
pub fn PollPlanStats::merged_points(self : PollPlanStats) -> Int {
  self.merged_points
}

///|
pub fn PollPlanStats::estimated_registers(self : PollPlanStats) -> Int {
  self.estimated_registers
}

///|
pub fn PollPlanStats::highest_priority(self : PollPlanStats) -> Int {
  self.highest_priority
}
