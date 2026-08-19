///|
/// Aggregated endpoint health used by operations dashboards.
pub(all) struct EndpointHealth {
  unit_id : Byte
  ready : Bool
  event_count : UInt16
  exceptions : Int
  requests : Int
  responses : Int
  errors : Int
}

///|
pub fn endpoint_health(
  device : Device,
  metrics : ProtocolMetrics,
) -> EndpointHealth {
  let health = device.health()
  {
    unit_id: health.unit_id,
    ready: !health.busy,
    event_count: health.event_count,
    exceptions: health.exception_count,
    requests: metrics.requests(),
    responses: metrics.responses(),
    errors: metrics.errors(),
  }
}

///|
/// Return a score in [0, 100] suitable for a small status indicator.
pub fn endpoint_score(health : EndpointHealth) -> Int {
  if !health.ready {
    return 0
  }
  let total = health.requests
  if total == 0 {
    return 100
  }
  let good = health.responses - health.errors - health.exceptions
  let score = good * 100 / total
  if score < 0 {
    0
  } else if score > 100 {
    100
  } else {
    score
  }
}

///|
/// Validate that endpoint counters are internally consistent.
pub fn validate_endpoint_health(
  health : EndpointHealth,
) -> Result[Unit, ModbusError] {
  if health.requests < 0 ||
    health.responses < 0 ||
    health.errors < 0 ||
    health.exceptions < 0 {
    Err(InvalidData)
  } else if health.responses > health.requests {
    Err(InvalidData)
  } else {
    Ok(())
  }
}

///|
/// Summarize health in stable key/value form for a CLI or metrics exporter.
pub fn endpoint_health_summary(health : EndpointHealth) -> String {
  "unit=" +
  health.unit_id.to_string() +
  " ready=" +
  (if health.ready { "true" } else { "false" }) +
  " score=" +
  endpoint_score(health).to_string() +
  " requests=" +
  health.requests.to_string() +
  " responses=" +
  health.responses.to_string() +
  " errors=" +
  health.errors.to_string()
}

///|
/// Compute an overall score for a fleet of devices.
pub fn fleet_score(health : Array[EndpointHealth]) -> Int {
  if health.length() == 0 {
    return 100
  }
  let mut total = 0
  for item in health {
    total += endpoint_score(item)
  }
  total / health.length()
}

///|
/// Return the least healthy endpoint, if any.
pub fn least_healthy(health : Array[EndpointHealth]) -> EndpointHealth? {
  if health.length() == 0 {
    return None
  }
  let mut result = health[0]
  for item in health {
    if endpoint_score(item) < endpoint_score(result) {
      result = item
    }
  }
  Some(result)
}
