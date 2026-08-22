///|
/// Fleet-level state derived from reliability, services, and inventory.
pub(all) enum FleetHealthState {
  FleetHealthy
  FleetDegraded
  FleetCritical
  FleetEmpty
} derive(Debug, Eq)

///|
/// A weighted health contribution from one subsystem.
pub(all) struct HealthContribution {
  source : String
  score : Int
  weight : Int
  detail : String
}

///|
pub fn HealthContribution::new(
  source : String,
  score : Int,
  weight : Int,
  detail : String,
) -> Result[HealthContribution, ModbusError] {
  if source == "" || score < 0 || score > 100 || weight < 1 || detail == "" {
    Err(InvalidData)
  } else {
    Ok({ source, score, weight, detail })
  }
}

///|
pub fn HealthContribution::source(self : HealthContribution) -> String {
  self.source
}

///|
pub fn HealthContribution::score(self : HealthContribution) -> Int {
  self.score
}

///|
pub fn HealthContribution::weight(self : HealthContribution) -> Int {
  self.weight
}

///|
pub fn HealthContribution::detail(self : HealthContribution) -> String {
  self.detail
}

///|
/// Weighted score calculation used by operator dashboards.
pub(all) struct FleetHealthRollup {
  contributions : Array[HealthContribution]
  mut score : Int
  mut state : FleetHealthState
  timestamp : Int
}

///|
pub fn FleetHealthRollup::new(
  timestamp : Int,
) -> Result[FleetHealthRollup, ModbusError] {
  if timestamp < 0 {
    Err(InvalidData)
  } else {
    Ok({ contributions: [], score: 0, state: FleetEmpty, timestamp })
  }
}

///|
pub fn FleetHealthRollup::timestamp(self : FleetHealthRollup) -> Int {
  self.timestamp
}

///|
pub fn FleetHealthRollup::score(self : FleetHealthRollup) -> Int {
  self.score
}

///|
pub fn FleetHealthRollup::state(self : FleetHealthRollup) -> FleetHealthState {
  self.state
}

///|
pub fn FleetHealthRollup::contribution_count(self : FleetHealthRollup) -> Int {
  self.contributions.length()
}

///|
pub fn FleetHealthRollup::add(
  self : FleetHealthRollup,
  contribution : HealthContribution,
) -> Result[Unit, ModbusError] {
  for existing in self.contributions {
    if existing.source() == contribution.source() {
      return Err(InvalidData)
    }
  }
  self.contributions.push(contribution)
  self.recalculate()
  Ok(())
}

///|
pub fn FleetHealthRollup::recalculate(self : FleetHealthRollup) -> Unit {
  if self.contributions.length() == 0 {
    self.score = 0
    self.state = FleetEmpty
    return
  }
  let mut weighted = 0
  let mut total_weight = 0
  for contribution in self.contributions {
    weighted += contribution.score() * contribution.weight()
    total_weight += contribution.weight()
  }
  self.score = weighted / total_weight
  self.state = if self.score >= 85 {
    FleetHealthy
  } else if self.score >= 60 {
    FleetDegraded
  } else {
    FleetCritical
  }
}

///|
pub fn FleetHealthRollup::contributions(
  self : FleetHealthRollup,
) -> Array[HealthContribution] {
  self.contributions
}

///|
pub fn FleetHealthRollup::contribution(
  self : FleetHealthRollup,
  source : String,
) -> HealthContribution? {
  for contribution in self.contributions {
    if contribution.source() == source {
      return Some(contribution)
    }
  }
  None
}

///|
pub fn FleetHealthRollup::remove(
  self : FleetHealthRollup,
  source : String,
) -> Result[HealthContribution, ModbusError] {
  for i in 0..<self.contributions.length() {
    if self.contributions[i].source() == source {
      let removed = self.contributions.remove(i)
      self.recalculate()
      return Ok(removed)
    }
  }
  Err(InvalidData)
}

///|
pub fn fleet_health_state_name(state : FleetHealthState) -> String {
  match state {
    FleetHealthy => "healthy"
    FleetDegraded => "degraded"
    FleetCritical => "critical"
    FleetEmpty => "empty"
  }
}

///|
/// Generate contributions from a reliability fleet summary.
pub fn fleet_health_from_reliability(
  timestamp : Int,
  summary : ReliabilityFleetSummary,
) -> Result[FleetHealthRollup, ModbusError] {
  let rollup = match FleetHealthRollup::new(timestamp) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let reliability = match
    HealthContribution::new(
      "reliability",
      summary.average_success_rate(),
      5,
      "success-rate",
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ignore(rollup.add(reliability))
  let latency_score = if summary.average_latency() >= 1000 {
    0
  } else {
    100 - summary.average_latency() / 10
  }
  let latency = match
    HealthContribution::new("latency", latency_score, 2, "average-latency") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ignore(rollup.add(latency))
  Ok(rollup)
}

///|
/// Generate contributions from a service registry.
pub fn fleet_health_from_services(
  rollup : FleetHealthRollup,
  registry : DeviceServiceRegistry,
) -> Result[Unit, ModbusError] {
  let total = registry.service_count()
  if total == 0 {
    return Ok(())
  }
  let running = registry.running().length()
  let score = running * 100 / total
  let contribution = match
    HealthContribution::new("services", score, 3, "running-services") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  rollup.add(contribution)
}

///|
/// Generate a contribution from inventory reachability.
pub fn fleet_health_from_inventory(
  rollup : FleetHealthRollup,
  inventory : DeviceInventory,
  now : Int,
  timeout : Int,
) -> Result[Unit, ModbusError] {
  let offline = match inventory.mark_stale(now, timeout) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let total = inventory.count()
  let score = if total == 0 { 0 } else { (total - offline) * 100 / total }
  let contribution = match
    HealthContribution::new("inventory", score, 4, "reachable-devices") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  rollup.add(contribution)
}

///|
/// A serializable health line for logs and support bundles.
pub fn FleetHealthRollup::export_lines(
  self : FleetHealthRollup,
) -> Array[String] {
  let lines : Array[String] = []
  lines.push(
    "fleet_state=" +
    fleet_health_state_name(self.state) +
    " score=" +
    self.score.to_string() +
    " timestamp=" +
    self.timestamp.to_string(),
  )
  for contribution in self.contributions {
    lines.push(
      "health_source=" +
      contribution.source() +
      " score=" +
      contribution.score().to_string() +
      " weight=" +
      contribution.weight().to_string() +
      " detail=" +
      contribution.detail(),
    )
  }
  lines
}
