///|
/// Priority used by the application-level request scheduler.
pub(all) enum JobPriority {
  Background
  NormalPriority
  HighPriority
  Emergency
} derive(Debug, Eq)

///|
/// Lifecycle state of a scheduled request.
pub(all) enum JobState {
  Ready
  InFlight
  Waiting
  Completed
  Failed
  Cancelled
} derive(Debug, Eq)

///|
/// Policy controlling retry count and backoff growth.
pub(all) struct RetryPolicy {
  max_attempts : Int
  initial_backoff : Int
  max_backoff : Int
  multiplier : Int
}

///|
pub fn RetryPolicy::new(
  max_attempts : Int,
  initial_backoff : Int,
  max_backoff : Int,
  multiplier? : Int = 2,
) -> Result[RetryPolicy, ModbusError] {
  if max_attempts < 1 ||
    initial_backoff < 0 ||
    max_backoff < initial_backoff ||
    multiplier < 1 {
    Err(InvalidData)
  } else {
    Ok({ max_attempts, initial_backoff, max_backoff, multiplier })
  }
}

///|
pub fn default_retry_policy() -> RetryPolicy {
  { max_attempts: 3, initial_backoff: 100, max_backoff: 5000, multiplier: 2 }
}

///|
pub fn RetryPolicy::max_attempts(self : RetryPolicy) -> Int {
  self.max_attempts
}

///|
pub fn RetryPolicy::initial_backoff(self : RetryPolicy) -> Int {
  self.initial_backoff
}

///|
pub fn RetryPolicy::max_backoff(self : RetryPolicy) -> Int {
  self.max_backoff
}

///|
pub fn RetryPolicy::multiplier(self : RetryPolicy) -> Int {
  self.multiplier
}

///|
pub fn RetryPolicy::backoff(
  self : RetryPolicy,
  attempt : Int,
) -> Result[Int, ModbusError] {
  if attempt < 1 || attempt > self.max_attempts {
    return Err(InvalidQuantity)
  }
  let mut result = self.initial_backoff
  for _ in 1..<attempt {
    if result > self.max_backoff / self.multiplier {
      result = self.max_backoff
    } else {
      result *= self.multiplier
    }
  }
  Ok(if result > self.max_backoff { self.max_backoff } else { result })
}

///|
pub fn RetryPolicy::can_retry(self : RetryPolicy, attempt : Int) -> Bool {
  attempt < self.max_attempts
}

///|
pub fn RetryPolicy::summary(self : RetryPolicy) -> String {
  "attempts=" +
  self.max_attempts.to_string() +
  " backoff=" +
  self.initial_backoff.to_string() +
  ".." +
  self.max_backoff.to_string() +
  " multiplier=" +
  self.multiplier.to_string()
}

///|
/// A request retained by the scheduler until it is dispatched or expires.
pub(all) struct ScheduledJob {
  id : String
  request : Frame
  priority : JobPriority
  period : Int
  deadline : Int
  policy : RetryPolicy
  mut due_at : Int
  mut attempts : Int
  mut state : JobState
  mut last_error : ModbusError?
  mut last_started : Int?
  mut last_finished : Int?
  tag : String
}

///|
pub fn ScheduledJob::new(
  id : String,
  request : Frame,
  due_at : Int,
  period? : Int = 0,
  priority? : JobPriority = NormalPriority,
  deadline? : Int = 0,
  policy? : RetryPolicy = default_retry_policy(),
  tag? : String = "",
) -> Result[ScheduledJob, ModbusError] {
  if id == "" || due_at < 0 || period < 0 || deadline < 0 {
    return Err(InvalidData)
  }
  match validate_frame(request, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok({
    id,
    request,
    priority,
    period,
    deadline,
    policy,
    due_at,
    attempts: 0,
    state: Ready,
    last_error: None,
    last_started: None,
    last_finished: None,
    tag,
  })
}

///|
pub fn ScheduledJob::id(self : ScheduledJob) -> String {
  self.id
}

///|
pub fn ScheduledJob::request(self : ScheduledJob) -> Frame {
  self.request
}

///|
pub fn ScheduledJob::priority(self : ScheduledJob) -> JobPriority {
  self.priority
}

///|
pub fn ScheduledJob::period(self : ScheduledJob) -> Int {
  self.period
}

///|
pub fn ScheduledJob::deadline(self : ScheduledJob) -> Int {
  self.deadline
}

///|
pub fn ScheduledJob::due_at(self : ScheduledJob) -> Int {
  self.due_at
}

///|
pub fn ScheduledJob::attempts(self : ScheduledJob) -> Int {
  self.attempts
}

///|
pub fn ScheduledJob::state(self : ScheduledJob) -> JobState {
  self.state
}

///|
pub fn ScheduledJob::tag(self : ScheduledJob) -> String {
  self.tag
}

///|
pub fn ScheduledJob::last_error(self : ScheduledJob) -> ModbusError? {
  self.last_error
}

///|
pub fn ScheduledJob::is_periodic(self : ScheduledJob) -> Bool {
  self.period > 0
}

///|
pub fn ScheduledJob::is_due(self : ScheduledJob, now : Int) -> Bool {
  self.state == Ready && now >= self.due_at
}

///|
pub fn ScheduledJob::is_expired(self : ScheduledJob, now : Int) -> Bool {
  self.deadline > 0 && now > self.due_at + self.deadline
}

///|
pub fn ScheduledJob::age(self : ScheduledJob, now : Int) -> Int {
  if now < self.due_at {
    0
  } else {
    now - self.due_at
  }
}

///|
pub fn ScheduledJob::start(
  self : ScheduledJob,
  now : Int,
) -> Result[Unit, ModbusError] {
  if self.state != Ready || now < self.due_at {
    return Err(Busy)
  }
  self.state = InFlight
  self.attempts += 1
  self.last_started = Some(now)
  Ok(())
}

///|
pub fn ScheduledJob::complete(
  self : ScheduledJob,
  now : Int,
) -> Result[Unit, ModbusError] {
  if self.state != InFlight {
    return Err(InvalidData)
  }
  self.last_finished = Some(now)
  self.last_error = None
  if self.period > 0 {
    self.state = Waiting
    self.due_at = now + self.period
    self.attempts = 0
  } else {
    self.state = Completed
  }
  Ok(())
}

///|
pub fn ScheduledJob::fail(
  self : ScheduledJob,
  error : ModbusError,
  now : Int,
) -> Result[Bool, ModbusError] {
  if self.state != InFlight {
    return Err(InvalidData)
  }
  self.last_error = Some(error)
  self.last_finished = Some(now)
  if self.policy.can_retry(self.attempts) {
    let delay = self.policy.backoff(self.attempts).unwrap()
    self.state = Waiting
    self.due_at = now + delay
    Ok(true)
  } else {
    self.state = Failed
    Ok(false)
  }
}

///|
pub fn ScheduledJob::cancel(self : ScheduledJob) -> Result[Unit, ModbusError] {
  if self.state == Completed || self.state == Failed {
    Err(InvalidData)
  } else {
    self.state = Cancelled
    Ok(())
  }
}

///|
pub fn ScheduledJob::reset(
  self : ScheduledJob,
  due_at : Int,
) -> Result[Unit, ModbusError] {
  if due_at < 0 {
    return Err(InvalidData)
  }
  self.due_at = due_at
  self.attempts = 0
  self.state = Ready
  self.last_error = None
  self.last_started = None
  self.last_finished = None
  Ok(())
}

///|
pub fn ScheduledJob::latency(self : ScheduledJob) -> Int? {
  match (self.last_started, self.last_finished) {
    (Some(start), Some(finish)) =>
      Some(if finish < start { 0 } else { finish - start })
    _ => None
  }
}

///|
pub fn job_priority_rank(priority : JobPriority) -> Int {
  match priority {
    Background => 0
    NormalPriority => 1
    HighPriority => 2
    Emergency => 3
  }
}

///|
pub fn job_state_name(state : JobState) -> String {
  match state {
    Ready => "ready"
    InFlight => "in-flight"
    Waiting => "waiting"
    Completed => "completed"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
/// A bounded scheduler with priority-aware due-job selection.
pub(all) struct JobScheduler {
  jobs : Array[ScheduledJob]
  max_jobs : Int
  mut now : Int
  mut dispatched : Int
  mut completed : Int
  mut failed : Int
  mut cancelled : Int
}

///|
pub fn JobScheduler::new(
  max_jobs? : Int = 256,
) -> Result[JobScheduler, ModbusError] {
  if max_jobs < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({
      jobs: [],
      max_jobs,
      now: 0,
      dispatched: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
    })
  }
}

///|
pub fn JobScheduler::length(self : JobScheduler) -> Int {
  self.jobs.length()
}

///|
pub fn JobScheduler::now(self : JobScheduler) -> Int {
  self.now
}

///|
pub fn JobScheduler::add(
  self : JobScheduler,
  job : ScheduledJob,
) -> Result[Unit, ModbusError] {
  if self.jobs.length() >= self.max_jobs {
    return Err(CapacityExceeded)
  }
  for current in self.jobs {
    if current.id() == job.id() {
      return Err(InvalidData)
    }
  }
  self.jobs.push(job)
  Ok(())
}

///|
pub fn JobScheduler::find(self : JobScheduler, id : String) -> ScheduledJob? {
  for job in self.jobs {
    if job.id() == id {
      return Some(job)
    }
  }
  None
}

///|
pub fn JobScheduler::get(
  self : JobScheduler,
  index : Int,
) -> Result[ScheduledJob, ModbusError] {
  if index < 0 || index >= self.jobs.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.jobs[index])
  }
}

///|
pub fn JobScheduler::snapshot(self : JobScheduler) -> Array[ScheduledJob] {
  let result : Array[ScheduledJob] = []
  for job in self.jobs {
    result.push(job)
  }
  result
}

///|
pub fn JobScheduler::remove(
  self : JobScheduler,
  id : String,
) -> Result[ScheduledJob, ModbusError] {
  for index, job in self.jobs {
    if job.id() == id {
      ignore(self.jobs.remove(index))
      if job.state() == Cancelled {
        self.cancelled += 1
      }
      return Ok(job)
    }
  }
  Err(InvalidData)
}

///|
fn scheduler_better(left : ScheduledJob, right : ScheduledJob) -> Bool {
  let left_rank = job_priority_rank(left.priority())
  let right_rank = job_priority_rank(right.priority())
  left_rank > right_rank ||
  (left_rank == right_rank && left.due_at() < right.due_at())
}

///|
pub fn JobScheduler::next_due(self : JobScheduler, now : Int) -> ScheduledJob? {
  let mut selected : ScheduledJob? = None
  for job in self.jobs {
    if job.is_due(now) {
      match selected {
        None => selected = Some(job)
        Some(current) =>
          if scheduler_better(job, current) {
            selected = Some(job)
          }
      }
    }
  }
  selected
}

///|
pub fn JobScheduler::dispatch(
  self : JobScheduler,
  now : Int,
) -> Result[ScheduledJob, ModbusError] {
  self.now = if now < self.now { self.now } else { now }
  let job = match self.next_due(self.now) {
    Some(value) => value
    None => return Err(Incomplete)
  }
  for index, current in self.jobs {
    if current.id() == job.id() {
      match current.start(self.now) {
        Err(error) => return Err(error)
        Ok(_) => {
          self.jobs[index] = current
          self.dispatched += 1
          return Ok(current)
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn JobScheduler::complete(
  self : JobScheduler,
  id : String,
  now : Int,
) -> Result[Unit, ModbusError] {
  for index, job in self.jobs {
    if job.id() == id {
      match job.complete(now) {
        Err(error) => return Err(error)
        Ok(_) => {
          self.jobs[index] = job
          self.completed += 1
          return Ok(())
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn JobScheduler::fail(
  self : JobScheduler,
  id : String,
  error : ModbusError,
  now : Int,
) -> Result[Bool, ModbusError] {
  for index, job in self.jobs {
    if job.id() == id {
      let retry = match job.fail(error, now) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.jobs[index] = job
      if !retry {
        self.failed += 1
      }
      return Ok(retry)
    }
  }
  Err(InvalidData)
}

///|
pub fn JobScheduler::cancel(
  self : JobScheduler,
  id : String,
) -> Result[Unit, ModbusError] {
  for index, job in self.jobs {
    if job.id() == id {
      match job.cancel() {
        Err(error) => return Err(error)
        Ok(_) => {
          self.jobs[index] = job
          self.cancelled += 1
          return Ok(())
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn JobScheduler::reschedule(
  self : JobScheduler,
  id : String,
  due_at : Int,
) -> Result[Unit, ModbusError] {
  for index, job in self.jobs {
    if job.id() == id {
      match job.reset(due_at) {
        Err(error) => return Err(error)
        Ok(_) => {
          self.jobs[index] = job
          return Ok(())
        }
      }
    }
  }
  Err(InvalidData)
}

///|
pub fn JobScheduler::due_count(self : JobScheduler, now : Int) -> Int {
  let mut count = 0
  for job in self.jobs {
    if job.is_due(now) {
      count += 1
    }
  }
  count
}

///|
pub fn JobScheduler::state_count(self : JobScheduler, state : JobState) -> Int {
  let mut count = 0
  for job in self.jobs {
    if job.state() == state {
      count += 1
    }
  }
  count
}

///|
pub fn JobScheduler::dispatched(self : JobScheduler) -> Int {
  self.dispatched
}

///|
pub fn JobScheduler::completed(self : JobScheduler) -> Int {
  self.completed
}

///|
pub fn JobScheduler::failed(self : JobScheduler) -> Int {
  self.failed
}

///|
pub fn JobScheduler::cancelled(self : JobScheduler) -> Int {
  self.cancelled
}

///|
pub fn JobScheduler::reset_metrics(self : JobScheduler) -> Unit {
  self.dispatched = 0
  self.completed = 0
  self.failed = 0
  self.cancelled = 0
}

///|
pub fn JobScheduler::summary(self : JobScheduler) -> String {
  "jobs=" +
  self.length().to_string() +
  " due=" +
  self.due_count(self.now).to_string() +
  " dispatched=" +
  self.dispatched.to_string() +
  " completed=" +
  self.completed.to_string() +
  " failed=" +
  self.failed.to_string()
}

///|
/// A compact schedule snapshot for metrics export.
pub(all) struct SchedulerSnapshot {
  total : Int
  ready : Int
  in_flight : Int
  waiting : Int
  completed : Int
  failed : Int
  cancelled : Int
}

///|
pub fn JobScheduler::snapshot_metrics(self : JobScheduler) -> SchedulerSnapshot {
  {
    total: self.jobs.length(),
    ready: self.state_count(Ready),
    in_flight: self.state_count(InFlight),
    waiting: self.state_count(Waiting),
    completed: self.state_count(Completed),
    failed: self.state_count(Failed),
    cancelled: self.state_count(Cancelled),
  }
}

///|
pub fn SchedulerSnapshot::healthy(self : SchedulerSnapshot) -> Bool {
  self.failed == 0
}

///|
pub fn SchedulerSnapshot::summary(self : SchedulerSnapshot) -> String {
  "total=" +
  self.total.to_string() +
  " ready=" +
  self.ready.to_string() +
  " in-flight=" +
  self.in_flight.to_string() +
  " waiting=" +
  self.waiting.to_string() +
  " completed=" +
  self.completed.to_string() +
  " failed=" +
  self.failed.to_string()
}
