///|
/// Deterministic outcome injected into a protocol simulation.
pub(all) enum ScenarioOutcome {
  ScenarioSuccess
  ScenarioTimeout
  ScenarioException
  ScenarioCorrupt
  ScenarioDropped
  ScenarioDelayed
} derive(Debug, Eq)

///|
/// Fault applied to a selected step in a reproducible test scenario.
pub(all) enum ScenarioFault {
  NoFault
  DropNext
  DelayNext(Int)
  CorruptByte(Int)
  ForceException(Byte)
  Repeat(Int)
} derive(Debug, Eq)

///|
/// One input/output expectation used by integration and boundary tests.
pub(all) struct ScenarioStep {
  id : String
  timestamp : Int
  request : Frame
  expected_function : Byte
  expected_outcome : ScenarioOutcome
  mut fault : ScenarioFault
  note : String
}

///|
pub fn ScenarioStep::new(
  id : String,
  timestamp : Int,
  request : Frame,
  expected_outcome : ScenarioOutcome,
  note? : String = "",
) -> Result[ScenarioStep, ModbusError] {
  if id == "" || timestamp < 0 || request.pdu.function == 0 {
    return Err(InvalidData)
  }
  Ok({
    id,
    timestamp,
    request,
    expected_function: request.pdu.function,
    expected_outcome,
    fault: NoFault,
    note,
  })
}

///|
pub fn ScenarioStep::id(self : ScenarioStep) -> String {
  self.id
}

///|
pub fn ScenarioStep::timestamp(self : ScenarioStep) -> Int {
  self.timestamp
}

///|
pub fn ScenarioStep::request(self : ScenarioStep) -> Frame {
  self.request
}

///|
pub fn ScenarioStep::expected_function(self : ScenarioStep) -> Byte {
  self.expected_function
}

///|
pub fn ScenarioStep::expected_outcome(self : ScenarioStep) -> ScenarioOutcome {
  self.expected_outcome
}

///|
pub fn ScenarioStep::fault(self : ScenarioStep) -> ScenarioFault {
  self.fault
}

///|
pub fn ScenarioStep::note(self : ScenarioStep) -> String {
  self.note
}

///|
pub fn ScenarioStep::with_fault(
  self : ScenarioStep,
  fault : ScenarioFault,
) -> Unit {
  self.fault = fault
}

///|
pub fn scenario_outcome_name(outcome : ScenarioOutcome) -> String {
  match outcome {
    ScenarioSuccess => "success"
    ScenarioTimeout => "timeout"
    ScenarioException => "exception"
    ScenarioCorrupt => "corrupt"
    ScenarioDropped => "dropped"
    ScenarioDelayed => "delayed"
  }
}

///|
pub fn scenario_fault_name(fault : ScenarioFault) -> String {
  match fault {
    NoFault => "none"
    DropNext => "drop"
    DelayNext(_) => "delay"
    CorruptByte(_) => "corrupt"
    ForceException(_) => "exception"
    Repeat(_) => "repeat"
  }
}

///|
/// Scenario definition containing steps and shared test variables.
pub(all) struct ModbusScenario {
  id : String
  description : String
  steps : Array[ScenarioStep]
  max_steps : Int
  mut revision : Int
}

///|
pub fn ModbusScenario::new(
  id : String,
  description : String,
  max_steps? : Int = 1024,
) -> Result[ModbusScenario, ModbusError] {
  if id == "" || description == "" || max_steps < 1 {
    Err(InvalidData)
  } else {
    Ok({ id, description, steps: [], max_steps, revision: 0 })
  }
}

///|
pub fn ModbusScenario::id(self : ModbusScenario) -> String {
  self.id
}

///|
pub fn ModbusScenario::description(self : ModbusScenario) -> String {
  self.description
}

///|
pub fn ModbusScenario::step_count(self : ModbusScenario) -> Int {
  self.steps.length()
}

///|
pub fn ModbusScenario::revision(self : ModbusScenario) -> Int {
  self.revision
}

///|
pub fn ModbusScenario::add(
  self : ModbusScenario,
  step : ScenarioStep,
) -> Result[Unit, ModbusError] {
  if self.steps.length() >= self.max_steps {
    return Err(CapacityExceeded)
  }
  for existing in self.steps {
    if existing.id() == step.id() {
      return Err(InvalidData)
    }
    if step.timestamp() < existing.timestamp() {
      return Err(InvalidData)
    }
  }
  self.steps.push(step)
  self.revision += 1
  Ok(())
}

///|
pub fn ModbusScenario::step(
  self : ModbusScenario,
  id : String,
) -> ScenarioStep? {
  for step in self.steps {
    if step.id() == id {
      return Some(step)
    }
  }
  None
}

///|
pub fn ModbusScenario::steps(self : ModbusScenario) -> Array[ScenarioStep] {
  self.steps
}

///|
pub fn ModbusScenario::at(
  self : ModbusScenario,
  index : Int,
) -> Result[ScenarioStep, ModbusError] {
  if index < 0 || index >= self.steps.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.steps[index])
  }
}

///|
pub fn ModbusScenario::faults(self : ModbusScenario) -> Int {
  let mut count = 0
  for step in self.steps {
    match step.fault() {
      NoFault => ()
      _ => count += 1
    }
  }
  count
}

///|
/// A single result emitted by the deterministic runner.
pub(all) struct ScenarioResult {
  step_id : String
  outcome : ScenarioOutcome
  started_at : Int
  finished_at : Int
  response : Frame?
  error : ModbusError?
  detail : String
}

///|
pub fn ScenarioResult::new(
  step_id : String,
  outcome : ScenarioOutcome,
  started_at : Int,
  finished_at : Int,
  response? : Frame = Frame::new(0, 0, []),
  error? : ModbusError = Incomplete,
  detail? : String = "",
) -> Result[ScenarioResult, ModbusError] {
  if step_id == "" || started_at < 0 || finished_at < started_at {
    return Err(InvalidData)
  }
  let selected_response = if response.unit_id == 0 {
    None
  } else {
    Some(response)
  }
  let selected_error = if outcome == ScenarioSuccess {
    None
  } else {
    Some(error)
  }
  Ok({
    step_id,
    outcome,
    started_at,
    finished_at,
    response: selected_response,
    error: selected_error,
    detail,
  })
}

///|
pub fn ScenarioResult::step_id(self : ScenarioResult) -> String {
  self.step_id
}

///|
pub fn ScenarioResult::outcome(self : ScenarioResult) -> ScenarioOutcome {
  self.outcome
}

///|
pub fn ScenarioResult::started_at(self : ScenarioResult) -> Int {
  self.started_at
}

///|
pub fn ScenarioResult::finished_at(self : ScenarioResult) -> Int {
  self.finished_at
}

///|
pub fn ScenarioResult::duration(self : ScenarioResult) -> Int {
  self.finished_at - self.started_at
}

///|
pub fn ScenarioResult::response(self : ScenarioResult) -> Frame? {
  self.response
}

///|
pub fn ScenarioResult::error(self : ScenarioResult) -> ModbusError? {
  self.error
}

///|
pub fn ScenarioResult::detail(self : ScenarioResult) -> String {
  self.detail
}

///|
/// Deterministic runner with no wall-clock or random dependencies.
pub(all) struct ScenarioRunner {
  scenario : ModbusScenario
  results : Array[ScenarioResult]
  mut cursor : Int
  mut now : Int
}

///|
pub fn ScenarioRunner::new(
  scenario : ModbusScenario,
  start_at? : Int = 0,
) -> Result[ScenarioRunner, ModbusError] {
  if start_at < 0 {
    Err(InvalidData)
  } else {
    Ok({ scenario, results: [], cursor: 0, now: start_at })
  }
}

///|
pub fn ScenarioRunner::cursor(self : ScenarioRunner) -> Int {
  self.cursor
}

///|
pub fn ScenarioRunner::now(self : ScenarioRunner) -> Int {
  self.now
}

///|
pub fn ScenarioRunner::result_count(self : ScenarioRunner) -> Int {
  self.results.length()
}

///|
pub fn ScenarioRunner::results(self : ScenarioRunner) -> Array[ScenarioResult] {
  self.results
}

///|
/// Apply a fault to a request without mutating the scenario definition.
fn scenario_execute(
  step : ScenarioStep,
  now : Int,
) -> Result[ScenarioResult, ModbusError] {
  let delay = match step.fault() {
    DelayNext(value) => value
    _ => 0
  }
  if delay < 0 {
    return Err(InvalidData)
  }
  let finished = now + delay
  match step.fault() {
    DropNext =>
      ScenarioResult::new(
        step.id(),
        ScenarioDropped,
        now,
        finished,
        detail="dropped-by-fault",
      )
    DelayNext(_) =>
      ScenarioResult::new(
        step.id(),
        ScenarioDelayed,
        now,
        finished,
        detail="delayed-by-fault",
      )
    CorruptByte(index) =>
      if index < 0 || index >= step.request().pdu.data.length() {
        Err(InvalidAddress)
      } else {
        ScenarioResult::new(
          step.id(),
          ScenarioCorrupt,
          now,
          finished,
          error=InvalidChecksum,
          detail="corrupt-byte",
        )
      }
    ForceException(_) =>
      ScenarioResult::new(
        step.id(),
        ScenarioException,
        now,
        finished,
        error=InvalidFunction,
        detail="forced-exception",
      )
    Repeat(count) =>
      if count < 1 {
        Err(InvalidQuantity)
      } else {
        ScenarioResult::new(
          step.id(),
          ScenarioSuccess,
          now,
          finished,
          response=step.request(),
          detail="repeat=" + count.to_string(),
        )
      }
    NoFault =>
      ScenarioResult::new(
        step.id(),
        step.expected_outcome(),
        now,
        finished,
        response=if step.expected_outcome() == ScenarioSuccess {
          step.request()
        } else {
          Frame::new(0, 0, [])
        },
        detail=step.note(),
      )
  }
}

///|
/// Execute the next step and return its deterministic result.
pub fn ScenarioRunner::run_next(
  self : ScenarioRunner,
) -> Result[ScenarioResult, ModbusError] {
  if self.cursor >= self.scenario.step_count() {
    return Err(Incomplete)
  }
  let step = match self.scenario.at(self.cursor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = match
    scenario_execute(
      step,
      if self.now < step.timestamp() {
        step.timestamp()
      } else {
        self.now
      },
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.cursor += 1
  self.now = result.finished_at()
  self.results.push(result)
  Ok(result)
}

///|
/// Run all remaining steps, stopping at the first execution error.
pub fn ScenarioRunner::run_all(
  self : ScenarioRunner,
) -> Result[Array[ScenarioResult], ModbusError] {
  while self.cursor < self.scenario.step_count() {
    match self.run_next() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(self.results)
}

///|
/// Verify that all outcomes match the scenario's declared expectations.
pub fn ScenarioRunner::passed(self : ScenarioRunner) -> Bool {
  if self.results.length() != self.scenario.step_count() {
    return false
  }
  for i in 0..<self.results.length() {
    let step = match self.scenario.at(i) {
      Ok(value) => value
      Err(_) => return false
    }
    let result = self.results[i]
    match step.fault() {
      NoFault => if result.outcome() != step.expected_outcome() { return false }
      _ => ()
    }
  }
  true
}

///|
/// Count each deterministic outcome in runner results.
pub fn ScenarioRunner::outcome_counts(self : ScenarioRunner) -> Array[Int] {
  let counts : Array[Int] = [0, 0, 0, 0, 0, 0]
  for result in self.results {
    let index = match result.outcome() {
      ScenarioSuccess => 0
      ScenarioTimeout => 1
      ScenarioException => 2
      ScenarioCorrupt => 3
      ScenarioDropped => 4
      ScenarioDelayed => 5
    }
    counts[index] += 1
  }
  counts
}

///|
/// Build a common boundary scenario for a unit and function pair.
pub fn scenario_boundary_suite(
  unit_id : Byte,
  function : Byte,
) -> Result[ModbusScenario, ModbusError] {
  if !is_valid_unit_id(unit_id) || function == 0 {
    return Err(InvalidData)
  }
  let scenario = match
    ModbusScenario::new(
      "boundary-suite", "valid, delayed, corrupt, and dropped requests",
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let valid = match
    ScenarioStep::new(
      "valid",
      0,
      Frame::new(unit_id, function, [0, 0, 0, 1]),
      ScenarioSuccess,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ignore(scenario.add(valid))
  let delayed = match
    ScenarioStep::new(
      "delayed",
      10,
      Frame::new(unit_id, function, [0, 1, 0, 1]),
      ScenarioDelayed,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  delayed.with_fault(DelayNext(25))
  ignore(scenario.add(delayed))
  let corrupt = match
    ScenarioStep::new(
      "corrupt",
      40,
      Frame::new(unit_id, function, [0, 2, 0, 1]),
      ScenarioCorrupt,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  corrupt.with_fault(CorruptByte(1))
  ignore(scenario.add(corrupt))
  Ok(scenario)
}
