///|
/// Resource tracked by a gateway or device service budget.
pub(all) enum CapacityResource {
  InFlightRequests
  PollRegisters
  CaptureBytes
  CommandQueue
  HistorianSamples
  AlarmEvents
} derive(Debug, Eq)

///|
/// A named resource limit with soft and hard thresholds.
pub(all) struct CapacityLimit {
  resource : CapacityResource
  name : String
  soft_limit : Int
  hard_limit : Int
  mut used : Int
}

///|
pub fn CapacityLimit::new(
  resource : CapacityResource,
  name : String,
  soft_limit : Int,
  hard_limit : Int,
) -> Result[CapacityLimit, ModbusError] {
  if name == "" || soft_limit < 0 || hard_limit < soft_limit {
    return Err(InvalidData)
  }
  Ok({ resource, name, soft_limit, hard_limit, used: 0 })
}

///|
pub fn CapacityLimit::resource(self : CapacityLimit) -> CapacityResource {
  self.resource
}

///|
pub fn CapacityLimit::name(self : CapacityLimit) -> String {
  self.name
}

///|
pub fn CapacityLimit::soft_limit(self : CapacityLimit) -> Int {
  self.soft_limit
}

///|
pub fn CapacityLimit::hard_limit(self : CapacityLimit) -> Int {
  self.hard_limit
}

///|
pub fn CapacityLimit::used(self : CapacityLimit) -> Int {
  self.used
}

///|
pub fn CapacityLimit::available(self : CapacityLimit) -> Int {
  self.hard_limit - self.used
}

///|
pub fn CapacityLimit::over_soft(self : CapacityLimit) -> Bool {
  self.used > self.soft_limit
}

///|
pub fn CapacityLimit::over_hard(self : CapacityLimit) -> Bool {
  self.used > self.hard_limit
}

///|
pub fn CapacityLimit::reserve(
  self : CapacityLimit,
  amount : Int,
) -> Result[Unit, ModbusError] {
  if amount < 1 {
    return Err(InvalidQuantity)
  }
  if self.used + amount > self.hard_limit {
    return Err(CapacityExceeded)
  }
  self.used += amount
  Ok(())
}

///|
pub fn CapacityLimit::release(
  self : CapacityLimit,
  amount : Int,
) -> Result[Unit, ModbusError] {
  if amount < 1 || amount > self.used {
    return Err(InvalidQuantity)
  }
  self.used -= amount
  Ok(())
}

///|
pub fn CapacityLimit::reset(self : CapacityLimit) -> Unit {
  self.used = 0
}

///|
pub fn capacity_resource_name(resource : CapacityResource) -> String {
  match resource {
    InFlightRequests => "in-flight-requests"
    PollRegisters => "poll-registers"
    CaptureBytes => "capture-bytes"
    CommandQueue => "command-queue"
    HistorianSamples => "historian-samples"
    AlarmEvents => "alarm-events"
  }
}

///|
/// A reservation returned to a caller so releases can be audited.
pub(all) struct CapacityReservation {
  id : String
  resource : CapacityResource
  amount : Int
  created_at : Int
  mut released : Bool
}

///|
pub fn CapacityReservation::new(
  id : String,
  resource : CapacityResource,
  amount : Int,
  created_at : Int,
) -> Result[CapacityReservation, ModbusError] {
  if id == "" || amount < 1 || created_at < 0 {
    Err(InvalidData)
  } else {
    Ok({ id, resource, amount, created_at, released: false })
  }
}

///|
pub fn CapacityReservation::id(self : CapacityReservation) -> String {
  self.id
}

///|
pub fn CapacityReservation::resource(
  self : CapacityReservation,
) -> CapacityResource {
  self.resource
}

///|
pub fn CapacityReservation::amount(self : CapacityReservation) -> Int {
  self.amount
}

///|
pub fn CapacityReservation::created_at(self : CapacityReservation) -> Int {
  self.created_at
}

///|
pub fn CapacityReservation::released(self : CapacityReservation) -> Bool {
  self.released
}

///|
pub fn CapacityReservation::mark_released(
  self : CapacityReservation,
) -> Result[Unit, ModbusError] {
  if self.released {
    Err(Busy)
  } else {
    self.released = true
    Ok(())
  }
}

///|
/// Multi-resource ledger for admission control.
pub(all) struct CapacityLedger {
  limits : Array[CapacityLimit]
  reservations : Array[CapacityReservation]
  max_reservations : Int
  mut sequence : Int
}

///|
pub fn CapacityLedger::new(
  max_reservations? : Int = 8192,
) -> Result[CapacityLedger, ModbusError] {
  if max_reservations < 1 {
    Err(InvalidData)
  } else {
    Ok({ limits: [], reservations: [], max_reservations, sequence: 0 })
  }
}

///|
pub fn CapacityLedger::limit_count(self : CapacityLedger) -> Int {
  self.limits.length()
}

///|
pub fn CapacityLedger::reservation_count(self : CapacityLedger) -> Int {
  self.reservations.length()
}

///|
pub fn CapacityLedger::add_limit(
  self : CapacityLedger,
  limit : CapacityLimit,
) -> Result[Unit, ModbusError] {
  for existing in self.limits {
    if existing.resource() == limit.resource() {
      return Err(InvalidData)
    }
  }
  self.limits.push(limit)
  Ok(())
}

///|
pub fn CapacityLedger::limit(
  self : CapacityLedger,
  resource : CapacityResource,
) -> CapacityLimit? {
  for limit in self.limits {
    if limit.resource() == resource {
      return Some(limit)
    }
  }
  None
}

///|
/// Reserve one resource atomically and create an expirable token.
pub fn CapacityLedger::reserve(
  self : CapacityLedger,
  resource : CapacityResource,
  amount : Int,
  now : Int,
) -> Result[CapacityReservation, ModbusError] {
  if now < 0 ||
    amount < 1 ||
    self.reservations.length() >= self.max_reservations {
    return Err(CapacityExceeded)
  }
  let limit = match self.limit(resource) {
    Some(value) => value
    None => return Err(InvalidData)
  }
  match limit.reserve(amount) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.sequence += 1
  let id = "reservation-" + self.sequence.to_string()
  let reservation = match CapacityReservation::new(id, resource, amount, now) {
    Ok(value) => value
    Err(error) => {
      ignore(limit.release(amount))
      return Err(error)
    }
  }
  self.reservations.push(reservation)
  Ok(reservation)
}

///|
/// Release a previously issued reservation exactly once.
pub fn CapacityLedger::release(
  self : CapacityLedger,
  reservation_id : String,
) -> Result[Unit, ModbusError] {
  for reservation in self.reservations {
    if reservation.id() == reservation_id {
      if reservation.released() {
        return Err(Busy)
      }
      let limit = match self.limit(reservation.resource()) {
        Some(value) => value
        None => return Err(InvalidData)
      }
      match limit.release(reservation.amount()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      return reservation.mark_released()
    }
  }
  Err(InvalidData)
}

///|
/// Expire all reservations older than a caller-supplied age.
pub fn CapacityLedger::expire(
  self : CapacityLedger,
  now : Int,
  age : Int,
) -> Result[Int, ModbusError] {
  if now < 0 || age < 0 {
    return Err(InvalidData)
  }
  let mut released = 0
  for reservation in self.reservations {
    if !reservation.released() && now - reservation.created_at() >= age {
      let limit = match self.limit(reservation.resource()) {
        Some(value) => value
        None => continue
      }
      ignore(limit.release(reservation.amount()))
      ignore(reservation.mark_released())
      released += 1
    }
  }
  Ok(released)
}

///|
/// Return resources currently above their soft limit.
pub fn CapacityLedger::pressure(
  self : CapacityLedger,
) -> Array[CapacityResource] {
  let result : Array[CapacityResource] = []
  for limit in self.limits {
    if limit.over_soft() {
      result.push(limit.resource())
    }
  }
  result
}

///|
/// Reset all limits and reservation tokens after a controlled restart.
pub fn CapacityLedger::reset(self : CapacityLedger) -> Unit {
  for limit in self.limits {
    limit.reset()
  }
  for reservation in self.reservations {
    ignore(reservation.mark_released())
  }
  self.reservations.clear()
}

///|
/// Human-readable capacity table for health endpoints.
pub fn CapacityLedger::export_lines(self : CapacityLedger) -> Array[String] {
  let lines : Array[String] = []
  for limit in self.limits {
    lines.push(
      capacity_resource_name(limit.resource()) +
      " name=" +
      limit.name() +
      " used=" +
      limit.used().to_string() +
      " soft=" +
      limit.soft_limit().to_string() +
      " hard=" +
      limit.hard_limit().to_string(),
    )
  }
  lines
}
