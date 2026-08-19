///|
/// A polling job with a deterministic logical-clock schedule.
pub(all) struct PollJob {
  id : Int
  name : String
  request : Frame
  interval : Int
  timeout : Int
  retries : Int
  mut next_due : Int
  mut attempts : Int
  mut runs : Int
  mut failures : Int
  mut last_response : Frame?
}

///|
pub fn PollJob::new(
  id : Int,
  name : String,
  request : Frame,
  interval? : Int = 1000,
  timeout? : Int = 250,
  retries? : Int = 1,
) -> Result[PollJob, ModbusError] {
  if id < 0 || interval < 1 || timeout < 1 || retries < 0 {
    Err(InvalidData)
  } else {
    Ok({
      id,
      name,
      request,
      interval,
      timeout,
      retries,
      next_due: 0,
      attempts: 0,
      runs: 0,
      failures: 0,
      last_response: None,
    })
  }
}

///|
pub fn PollJob::is_due(self : PollJob, now : Int) -> Bool {
  now >= self.next_due
}

///|
pub fn PollJob::mark_success(
  self : PollJob,
  now : Int,
  response : Frame,
) -> Unit {
  self.runs += 1
  self.attempts = 0
  self.last_response = Some(response)
  self.next_due = now + self.interval
}

///|
pub fn PollJob::mark_failure(self : PollJob, now : Int) -> Unit {
  self.failures += 1
  self.attempts += 1
  if self.attempts > self.retries {
    self.attempts = 0
    self.next_due = now + self.interval
  } else {
    let backoff = self.timeout * (1 << (self.attempts - 1))
    self.next_due = now + backoff
  }
}

///|
pub fn PollJob::success_rate(self : PollJob) -> Float {
  let total = self.runs + self.failures
  if total == 0 {
    1.0
  } else {
    Float::from_int(self.runs) / Float::from_int(total)
  }
}

///|
/// A polling plan keeps jobs ordered and addresses them by stable ids.
pub struct PollPlan {
  jobs : Array[PollJob]
  max_jobs : Int
}

///|
pub fn PollPlan::new(max_jobs? : Int = 256) -> Result[PollPlan, ModbusError] {
  if max_jobs < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ jobs: [], max_jobs })
  }
}

///|
pub fn PollPlan::add(
  self : PollPlan,
  job : PollJob,
) -> Result[Unit, ModbusError] {
  if self.jobs.length() >= self.max_jobs {
    return Err(CapacityExceeded)
  }
  for existing in self.jobs {
    if existing.id == job.id || existing.name == job.name {
      return Err(InvalidData)
    }
  }
  self.jobs.push(job)
  Ok(())
}

///|
pub fn PollPlan::remove(self : PollPlan, id : Int) -> Result[Unit, ModbusError] {
  let found = self.find_index(id)
  match found {
    None => Err(InvalidAddress)
    Some(index) => {
      let remaining : Array[PollJob] = []
      for current in 0..<self.jobs.length() {
        if current != index {
          remaining.push(self.jobs[current])
        }
      }
      self.jobs.clear()
      for item in remaining {
        self.jobs.push(item)
      }
      Ok(())
    }
  }
}

///|
pub fn PollPlan::length(self : PollPlan) -> Int {
  self.jobs.length()
}

///|
pub fn PollPlan::job(self : PollPlan, id : Int) -> PollJob? {
  match self.find_index(id) {
    Some(index) => Some(self.jobs[index])
    None => None
  }
}

///|
pub fn PollPlan::due(self : PollPlan, now : Int) -> Array[PollJob] {
  let out : Array[PollJob] = []
  for job in self.jobs {
    if job.is_due(now) {
      out.push(job)
    }
  }
  out
}

///|
pub fn PollPlan::mark_success(
  self : PollPlan,
  id : Int,
  now : Int,
  response : Frame,
) -> Result[Unit, ModbusError] {
  match self.find_index(id) {
    None => Err(InvalidAddress)
    Some(index) => {
      self.jobs[index].mark_success(now, response)
      Ok(())
    }
  }
}

///|
pub fn PollPlan::mark_failure(
  self : PollPlan,
  id : Int,
  now : Int,
) -> Result[Unit, ModbusError] {
  match self.find_index(id) {
    None => Err(InvalidAddress)
    Some(index) => {
      self.jobs[index].mark_failure(now)
      Ok(())
    }
  }
}

///|
pub fn PollPlan::snapshot(self : PollPlan) -> Array[PollJob] {
  let out : Array[PollJob] = []
  for job in self.jobs {
    out.push(job)
  }
  out
}

///|
fn PollPlan::find_index(self : PollPlan, id : Int) -> Int? {
  for index in 0..<self.jobs.length() {
    if self.jobs[index].id == id {
      return Some(index)
    }
  }
  None
}

///|
/// One scheduler run result.
pub(all) struct PollReport {
  now : Int
  attempted : Int
  succeeded : Int
  failed : Int
  responses : Array[Frame]
}

///|
/// Execute due jobs against a deterministic device.
pub fn PollPlan::run_once(
  self : PollPlan,
  device : Device,
  now : Int,
) -> PollReport {
  let due = self.due(now)
  let responses : Array[Frame] = []
  let mut succeeded = 0
  let mut failed = 0
  for job in due {
    match device.handle(job.request) {
      Ok(response) => {
        let _ = self.mark_success(job.id, now, response)
        responses.push(response)
        succeeded += 1
      }
      Err(_) => {
        let _ = self.mark_failure(job.id, now)
        failed += 1
      }
    }
  }
  { now, attempted: due.length(), succeeded, failed, responses }
}

///|
/// A scheduler that records the last report and applies a transport mode.
pub struct PollScheduler {
  plan : PollPlan
  device : Device
  mode : Mode
  mut last_report : PollReport?
}

///|
pub fn PollScheduler::new(
  plan : PollPlan,
  device : Device,
  mode : Mode,
) -> PollScheduler {
  { plan, device, mode, last_report: None }
}

///|
pub fn PollScheduler::tick(self : PollScheduler, now : Int) -> PollReport {
  let report = self.plan.run_once(self.device, now)
  self.last_report = Some(report)
  report
}

///|
pub fn PollScheduler::plan(self : PollScheduler) -> PollPlan {
  self.plan
}

///|
pub fn PollScheduler::mode(self : PollScheduler) -> Mode {
  self.mode
}

///|
pub fn PollScheduler::last_report(self : PollScheduler) -> PollReport? {
  self.last_report
}

///|
/// Validate plan timing invariants before deployment.
pub fn validate_poll_plan(plan : PollPlan) -> Result[Unit, ModbusError] {
  let jobs = plan.snapshot()
  for job in jobs {
    if job.interval < job.timeout || job.timeout < 1 {
      return Err(InvalidData)
    }
    match validate_frame(job.request, false) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}
