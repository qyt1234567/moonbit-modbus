///|
/// Ownership state for a serial line, TCP endpoint, or device command lane.
pub(all) enum LeaseState {
  LeaseAvailable
  LeaseHeld
  LeaseExpired
  LeaseRevoked
} derive(Debug, Eq)

///|
/// A time-bounded exclusive lease with renewal history.
pub(all) struct ResourceLease {
  id : String
  resource : String
  owner : String
  acquired_at : Int
  mut expires_at : Int
  mut state : LeaseState
  mut renewals : Int
  priority : Int
}

///|
pub fn ResourceLease::new(
  id : String,
  resource : String,
  owner : String,
  acquired_at : Int,
  duration : Int,
  priority? : Int = 0,
) -> Result[ResourceLease, ModbusError] {
  if id == "" ||
    resource == "" ||
    owner == "" ||
    acquired_at < 0 ||
    duration < 1 ||
    priority < 0 {
    return Err(InvalidData)
  }
  Ok({
    id,
    resource,
    owner,
    acquired_at,
    expires_at: acquired_at + duration,
    state: LeaseHeld,
    renewals: 0,
    priority,
  })
}

///|
pub fn ResourceLease::id(self : ResourceLease) -> String {
  self.id
}

///|
pub fn ResourceLease::resource(self : ResourceLease) -> String {
  self.resource
}

///|
pub fn ResourceLease::owner(self : ResourceLease) -> String {
  self.owner
}

///|
pub fn ResourceLease::acquired_at(self : ResourceLease) -> Int {
  self.acquired_at
}

///|
pub fn ResourceLease::expires_at(self : ResourceLease) -> Int {
  self.expires_at
}

///|
pub fn ResourceLease::state(self : ResourceLease) -> LeaseState {
  self.state
}

///|
pub fn ResourceLease::renewals(self : ResourceLease) -> Int {
  self.renewals
}

///|
pub fn ResourceLease::priority(self : ResourceLease) -> Int {
  self.priority
}

///|
pub fn ResourceLease::active(self : ResourceLease, now : Int) -> Bool {
  self.state == LeaseHeld && now >= self.acquired_at && now < self.expires_at
}

///|
pub fn ResourceLease::renew(
  self : ResourceLease,
  now : Int,
  duration : Int,
) -> Result[Unit, ModbusError] {
  if now < self.acquired_at ||
    duration < 1 ||
    self.state != LeaseHeld ||
    now >= self.expires_at {
    return Err(Busy)
  }
  self.expires_at = now + duration
  self.renewals += 1
  Ok(())
}

///|
pub fn ResourceLease::expire(
  self : ResourceLease,
  now : Int,
) -> Result[Unit, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  if self.state == LeaseHeld && now >= self.expires_at {
    self.state = LeaseExpired
  }
  Ok(())
}

///|
pub fn ResourceLease::revoke(self : ResourceLease) -> Result[Unit, ModbusError] {
  if self.state != LeaseHeld {
    Err(Busy)
  } else {
    self.state = LeaseRevoked
    Ok(())
  }
}

///|
pub fn lease_state_name(state : LeaseState) -> String {
  match state {
    LeaseAvailable => "available"
    LeaseHeld => "held"
    LeaseExpired => "expired"
    LeaseRevoked => "revoked"
  }
}

///|
/// Manages exclusive resource ownership across client workers.
pub(all) struct LeaseManager {
  leases : Array[ResourceLease]
  max_leases : Int
  default_duration : Int
  mut sequence : Int
}

///|
pub fn LeaseManager::new(
  max_leases? : Int = 1024,
  default_duration? : Int = 5000,
) -> Result[LeaseManager, ModbusError] {
  if max_leases < 1 || default_duration < 1 {
    Err(InvalidData)
  } else {
    Ok({ leases: [], max_leases, default_duration, sequence: 0 })
  }
}

///|
pub fn LeaseManager::count(self : LeaseManager) -> Int {
  self.leases.length()
}

///|
pub fn LeaseManager::default_duration(self : LeaseManager) -> Int {
  self.default_duration
}

///|
pub fn LeaseManager::find(
  self : LeaseManager,
  resource : String,
) -> ResourceLease? {
  for lease in self.leases {
    if lease.resource() == resource && lease.state() == LeaseHeld {
      return Some(lease)
    }
  }
  None
}

///|
/// Acquire a resource if no active lease has a higher or equal priority.
pub fn LeaseManager::acquire(
  self : LeaseManager,
  resource : String,
  owner : String,
  now : Int,
  priority? : Int = 0,
) -> Result[ResourceLease, ModbusError] {
  if resource == "" || owner == "" || now < 0 || priority < 0 {
    return Err(InvalidData)
  }
  for existing in self.leases {
    ignore(existing.expire(now))
    if existing.resource() == resource && existing.active(now) {
      if existing.priority() >= priority {
        return Err(Busy)
      }
      ignore(existing.revoke())
    }
  }
  if self.leases.length() >= self.max_leases {
    return Err(CapacityExceeded)
  }
  self.sequence += 1
  let id = "lease-" + self.sequence.to_string()
  let lease = match
    ResourceLease::new(
      id,
      resource,
      owner,
      now,
      self.default_duration,
      priority~,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.leases.push(lease)
  Ok(lease)
}

///|
/// Renew a lease only for its current owner.
pub fn LeaseManager::renew(
  self : LeaseManager,
  lease_id : String,
  owner : String,
  now : Int,
  duration? : Int = 0,
) -> Result[Unit, ModbusError] {
  if lease_id == "" || owner == "" {
    return Err(InvalidData)
  }
  let selected_duration = if duration == 0 {
    self.default_duration
  } else {
    duration
  }
  for lease in self.leases {
    if lease.id() == lease_id {
      if lease.owner() != owner {
        return Err(Unsupported)
      }
      return lease.renew(now, selected_duration)
    }
  }
  Err(InvalidData)
}

///|
/// Release a lease at the end of a request or connection.
pub fn LeaseManager::release(
  self : LeaseManager,
  lease_id : String,
  owner : String,
) -> Result[Unit, ModbusError] {
  for lease in self.leases {
    if lease.id() == lease_id {
      if lease.owner() != owner {
        return Err(Unsupported)
      }
      return lease.revoke()
    }
  }
  Err(InvalidData)
}

///|
/// Expire inactive leases and return their count.
pub fn LeaseManager::expire(
  self : LeaseManager,
  now : Int,
) -> Result[Int, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let mut count = 0
  for lease in self.leases {
    let before = lease.state()
    ignore(lease.expire(now))
    if before == LeaseHeld && lease.state() == LeaseExpired {
      count += 1
    }
  }
  Ok(count)
}

///|
/// Return active leases for a given owner.
pub fn LeaseManager::owned_by(
  self : LeaseManager,
  owner : String,
  now : Int,
) -> Result[Array[String], ModbusError] {
  if owner == "" || now < 0 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for lease in self.leases {
    if lease.owner() == owner && lease.active(now) {
      result.push(lease.resource())
    }
  }
  Ok(result)
}

///|
/// Clean up old terminal leases while retaining recent history.
pub fn LeaseManager::compact(
  self : LeaseManager,
  before : Int,
) -> Result[Int, ModbusError] {
  if before < 0 {
    return Err(InvalidData)
  }
  let mut removed = 0
  let mut index = 0
  while index < self.leases.length() {
    let lease = self.leases[index]
    if lease.state() != LeaseHeld && lease.expires_at() < before {
      ignore(self.leases.remove(index))
      removed += 1
    } else {
      index += 1
    }
  }
  Ok(removed)
}

///|
/// Return resource names with an active owner.
pub fn LeaseManager::active_resources(
  self : LeaseManager,
  now : Int,
) -> Result[Array[String], ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for lease in self.leases {
    if lease.active(now) {
      result.push(lease.resource())
    }
  }
  Ok(result)
}
