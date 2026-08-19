///|
/// A structured preflight report for deployment and CI diagnostics.
pub(all) struct PreflightReport {
  errors : Array[String]
  warnings : Array[String]
  mut checked_frames : Int
  mut checked_devices : Int
}

///|
pub fn PreflightReport::new() -> PreflightReport {
  { errors: [], warnings: [], checked_frames: 0, checked_devices: 0 }
}

///|
pub fn PreflightReport::ok(self : PreflightReport) -> Bool {
  self.errors.length() == 0
}

///|
pub fn PreflightReport::error_count(self : PreflightReport) -> Int {
  self.errors.length()
}

///|
pub fn PreflightReport::warning_count(self : PreflightReport) -> Int {
  self.warnings.length()
}

///|
pub fn PreflightReport::errors(self : PreflightReport) -> Array[String] {
  copy_strings(self.errors)
}

///|
pub fn PreflightReport::warnings(self : PreflightReport) -> Array[String] {
  copy_strings(self.warnings)
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for value in values {
    out.push(value)
  }
  out
}

///|
/// Check a frame's unit, PDU shape, and transport envelope constraints.
pub fn preflight_frame(
  report : PreflightReport,
  mode : Mode,
  frame : Frame,
) -> Unit {
  report.checked_frames += 1
  match validate_frame(frame, false) {
    Ok(_) => ()
    Err(error) =>
      report.errors.push(
        function_name(frame.pdu.function) + ": " + error_name(error),
      )
  }
  if encoded_length(mode, frame) > limits_for(mode).max_adu {
    report.errors.push("encoded frame exceeds " + mode_name(mode) + " limit")
  }
  if frame.pdu.data.length() == 0 {
    report.warnings.push(
      function_name(frame.pdu.function) + " has an empty data payload",
    )
  }
}

///|
/// Check a device's table capacities and unit id.
pub fn preflight_device(report : PreflightReport, device : Device) -> Unit {
  report.checked_devices += 1
  if !is_valid_unit_id(device.unit_id(), broadcast=false) {
    report.errors.push("device unit id is invalid")
  }
  if device.memory().coils().length() == 0 {
    report.warnings.push("device has no coil capacity")
  }
  if device.memory().holding_registers().length() == 0 {
    report.warnings.push("device has no holding-register capacity")
  }
}

///|
/// Check every job in a polling plan.
pub fn preflight_plan(
  report : PreflightReport,
  plan : PollPlan,
  mode : Mode,
) -> Unit {
  match validate_poll_plan(plan) {
    Ok(_) => ()
    Err(error) => report.errors.push("poll plan: " + error_name(error))
  }
  for job in plan.snapshot() {
    preflight_frame(report, mode, job.request)
  }
}

///|
/// Validate a complete server configuration and its registered devices.
pub fn preflight_server(server : Server) -> PreflightReport {
  let report = PreflightReport::new()
  match validate_server_config(server.config()) {
    Ok(_) => ()
    Err(error) => report.errors.push("server config: " + error_name(error))
  }
  for unit_id in 1..<=247 {
    match server.device(unit_id.to_byte()) {
      Some(device) => preflight_device(report, device)
      None => ()
    }
  }
  report
}

///|
/// Return a compact result line for CI logs.
pub fn preflight_summary(report : PreflightReport) -> String {
  "preflight errors=" +
  report.error_count().to_string() +
  " warnings=" +
  report.warning_count().to_string() +
  " frames=" +
  report.checked_frames.to_string() +
  " devices=" +
  report.checked_devices.to_string()
}
