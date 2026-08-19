///|
/// Lifecycle of a client-side exchange.
pub(all) enum ExchangeState {
  Pending
  Completed
  Failed
  Cancelled
} derive(Debug, Eq)

///|
/// Client retry and framing policy.
pub(all) struct ClientConfig {
  timeout_ticks : Int
  retries : Int
  max_pending : Int
  strict_unit : Bool
}

///|
pub fn default_client_config() -> ClientConfig {
  { timeout_ticks: 1000, retries: 2, max_pending: 32, strict_unit: true }
}

///|
/// A request prepared for a transport adapter.
pub(all) struct ClientRequest {
  transaction_id : UInt16
  frame : Frame
  bytes : Array[Byte]
}

///|
pub fn ClientRequest::encoded_length(self : ClientRequest) -> Int {
  self.bytes.length()
}

///|
/// A pending exchange retained for correlation and retry accounting.
pub(all) struct PendingExchange {
  transaction_id : UInt16
  frame : Frame
  mut attempts : Int
  created_at : Int
  mut last_sent_at : Int
  mut state : ExchangeState
}

///|
/// A stateful protocol client that does not assume a particular socket runtime.
pub struct Client {
  mode : Mode
  config : ClientConfig
  mut next_transaction : UInt16
  pending : Array[PendingExchange]
}

///|
pub fn Client::new(
  mode : Mode,
  config? : ClientConfig = default_client_config(),
) -> Client {
  { mode, config, next_transaction: 0, pending: [] }
}

///|
pub fn Client::mode(self : Client) -> Mode {
  self.mode
}

///|
pub fn Client::config(self : Client) -> ClientConfig {
  self.config
}

///|
pub fn Client::next_transaction(self : Client) -> UInt16 {
  self.next_transaction
}

///|
/// Allocate a non-zero transaction id for TCP and a stable zero id for serial modes.
pub fn Client::allocate_transaction(self : Client) -> UInt16 {
  match self.mode {
    Tcp => {
      self.next_transaction += 1
      if self.next_transaction == 0 {
        self.next_transaction = 1
      }
      self.next_transaction
    }
    _ => 0
  }
}

///|
/// Begin an exchange at logical tick zero.
pub fn Client::begin(
  self : Client,
  frame : Frame,
) -> Result[ClientRequest, ModbusError] {
  self.begin_at(frame, 0)
}

///|
/// Begin an exchange at a caller-supplied logical tick.
pub fn Client::begin_at(
  self : Client,
  frame : Frame,
  now : Int,
) -> Result[ClientRequest, ModbusError] {
  if self.pending_active() >= self.config.max_pending {
    return Err(Busy)
  }
  if self.config.strict_unit &&
    !is_valid_unit_id(frame.unit_id, broadcast=false) {
    return Err(InvalidUnitId)
  }
  match validate_frame(frame, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let transaction_id = self.allocate_transaction()
  let bytes = match try_encode_mode(self.mode, transaction_id, frame) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.pending.push({
    transaction_id,
    frame,
    attempts: 1,
    created_at: now,
    last_sent_at: now,
    state: Pending,
  })
  Ok({ transaction_id, frame, bytes })
}

///|
/// Accept bytes from the transport and correlate them with a pending request.
pub fn Client::accept(
  self : Client,
  request : ClientRequest,
  bytes : Array[Byte],
) -> Result[Frame, ModbusError] {
  let (transaction_id, response) = match decode_transaction(self.mode, bytes) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if self.mode == Tcp && transaction_id != request.transaction_id {
    self.mark_failed(request.transaction_id)
    return Err(InvalidTransaction)
  }
  match validate_response_header(request.frame, response) {
    Err(error) => {
      self.mark_failed(request.transaction_id)
      Err(error)
    }
    Ok(_) => {
      self.mark_completed(request.transaction_id)
      Ok(response)
    }
  }
}

///|
/// Accept an already decoded response frame.
pub fn Client::accept_frame(
  self : Client,
  request : ClientRequest,
  transaction_id : UInt16,
  response : Frame,
) -> Result[Frame, ModbusError] {
  if self.mode == Tcp && transaction_id != request.transaction_id {
    self.mark_failed(request.transaction_id)
    return Err(InvalidTransaction)
  }
  match validate_response_header(request.frame, response) {
    Err(error) => {
      self.mark_failed(request.transaction_id)
      Err(error)
    }
    Ok(_) => {
      self.mark_completed(request.transaction_id)
      Ok(response)
    }
  }
}

///|
/// Mark all timed-out exchanges as failed and return their transaction ids.
pub fn Client::expire(self : Client, now : Int) -> Array[UInt16] {
  let expired : Array[UInt16] = []
  for pending in self.pending {
    if pending.state == Pending &&
      now - pending.last_sent_at >= self.config.timeout_ticks {
      expired.push(pending.transaction_id)
    }
  }
  for transaction_id in expired {
    self.mark_failed(transaction_id)
  }
  expired
}

///|
/// Return pending exchanges that can be retried at a logical tick.
pub fn Client::retry_due(self : Client, now : Int) -> Array[UInt16] {
  let due : Array[UInt16] = []
  for index in 0..<self.pending.length() {
    let pending = self.pending[index]
    if pending.state == Pending &&
      now - pending.last_sent_at >= self.config.timeout_ticks {
      if pending.attempts <= self.config.retries {
        self.pending[index].attempts += 1
        self.pending[index].last_sent_at = now
        due.push(pending.transaction_id)
      } else {
        self.pending[index].state = Failed
      }
    }
  }
  due
}

///|
/// Find a pending request by transaction id.
pub fn Client::pending_request(
  self : Client,
  transaction_id : UInt16,
) -> PendingExchange? {
  for pending in self.pending {
    if pending.transaction_id == transaction_id && pending.state == Pending {
      return Some(pending)
    }
  }
  None
}

///|
pub fn Client::pending_active(self : Client) -> Int {
  let mut count = 0
  for pending in self.pending {
    if pending.state == Pending {
      count += 1
    }
  }
  count
}

///|
pub fn Client::completed_count(self : Client) -> Int {
  let mut count = 0
  for pending in self.pending {
    if pending.state == Completed {
      count += 1
    }
  }
  count
}

///|
pub fn Client::failed_count(self : Client) -> Int {
  let mut count = 0
  for pending in self.pending {
    if pending.state == Failed || pending.state == Cancelled {
      count += 1
    }
  }
  count
}

///|
pub fn Client::cancel(
  self : Client,
  transaction_id : UInt16,
) -> Result[Unit, ModbusError] {
  for index in 0..<self.pending.length() {
    if self.pending[index].transaction_id == transaction_id &&
      self.pending[index].state == Pending {
      self.pending[index].state = Cancelled
      return Ok(())
    }
  }
  Err(InvalidTransaction)
}

///|
fn Client::mark_completed(self : Client, transaction_id : UInt16) -> Unit {
  for index in 0..<self.pending.length() {
    if self.pending[index].transaction_id == transaction_id {
      self.pending[index].state = Completed
    }
  }
}

///|
fn Client::mark_failed(self : Client, transaction_id : UInt16) -> Unit {
  for index in 0..<self.pending.length() {
    if self.pending[index].transaction_id == transaction_id {
      self.pending[index].state = Failed
    }
  }
}

///|
/// Return a copy of all pending records for an external scheduler.
pub fn Client::pending_snapshot(self : Client) -> Array[PendingExchange] {
  let out : Array[PendingExchange] = []
  for pending in self.pending {
    out.push(pending)
  }
  out
}

///|
/// A decoded client result with a typed success/exception branch.
pub(all) enum ClientResult {
  Success(Frame)
  Exception(ExceptionCode)
}

///|
pub fn client_result(response : Frame) -> ClientResult {
  match exception_from_frame(response) {
    Ok(code) => Exception(code)
    Err(_) => Success(response)
  }
}

///|
/// Return a request's retry count, or zero when it is not tracked.
pub fn Client::attempts(self : Client, transaction_id : UInt16) -> Int {
  match self.pending_request(transaction_id) {
    Some(pending) => pending.attempts
    None => 0
  }
}
