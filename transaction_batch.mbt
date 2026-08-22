///|
/// Lifecycle state for a multi-request transaction.
pub(all) enum TransactionState {
  TransactionOpen
  TransactionPrepared
  TransactionCommitted
  TransactionRolledBack
  TransactionFailed
} derive(Debug, Eq)

///|
/// A request in a transaction with an optional compensation frame.
pub(all) struct TransactionItem {
  id : String
  request : Frame
  compensation : Frame?
  mut state : TransactionState
  order : Int
}

///|
pub fn TransactionItem::new(
  id : String,
  request : Frame,
  order : Int,
  compensation? : Frame = Frame::new(0, 0, []),
) -> Result[TransactionItem, ModbusError] {
  if id == "" || order < 0 || request.pdu.function == 0 {
    return Err(InvalidData)
  }
  let selected = if compensation.unit_id == 0 {
    None
  } else {
    Some(compensation)
  }
  Ok({ id, request, compensation: selected, state: TransactionOpen, order })
}

///|
pub fn TransactionItem::id(self : TransactionItem) -> String {
  self.id
}

///|
pub fn TransactionItem::request(self : TransactionItem) -> Frame {
  self.request
}

///|
pub fn TransactionItem::compensation(self : TransactionItem) -> Frame? {
  self.compensation
}

///|
pub fn TransactionItem::state(self : TransactionItem) -> TransactionState {
  self.state
}

///|
pub fn TransactionItem::order(self : TransactionItem) -> Int {
  self.order
}

///|
pub fn TransactionItem::mark(
  self : TransactionItem,
  state : TransactionState,
) -> Unit {
  self.state = state
}

///|
/// A transaction result with response and error context.
pub(all) struct TransactionOutcome {
  item_id : String
  state : TransactionState
  response : Frame?
  error : ModbusError?
  timestamp : Int
}

///|
pub fn TransactionOutcome::new(
  item_id : String,
  state : TransactionState,
  timestamp : Int,
  response? : Frame = Frame::new(0, 0, []),
  error? : ModbusError = Incomplete,
) -> Result[TransactionOutcome, ModbusError] {
  if item_id == "" || timestamp < 0 {
    return Err(InvalidData)
  }
  let selected_response = if response.unit_id == 0 {
    None
  } else {
    Some(response)
  }
  let selected_error = if state == TransactionCommitted {
    None
  } else {
    Some(error)
  }
  Ok({
    item_id,
    state,
    response: selected_response,
    error: selected_error,
    timestamp,
  })
}

///|
pub fn TransactionOutcome::item_id(self : TransactionOutcome) -> String {
  self.item_id
}

///|
pub fn TransactionOutcome::state(self : TransactionOutcome) -> TransactionState {
  self.state
}

///|
pub fn TransactionOutcome::response(self : TransactionOutcome) -> Frame? {
  self.response
}

///|
pub fn TransactionOutcome::error(self : TransactionOutcome) -> ModbusError? {
  self.error
}

///|
pub fn TransactionOutcome::timestamp(self : TransactionOutcome) -> Int {
  self.timestamp
}

///|
/// Ordered transaction coordinator for write-and-verify workflows.
pub(all) struct ModbusTransaction {
  id : String
  unit_id : Byte
  items : Array[TransactionItem]
  outcomes : Array[TransactionOutcome]
  max_items : Int
  mut state : TransactionState
  mut next_order : Int
}

///|
pub fn ModbusTransaction::new(
  id : String,
  unit_id : Byte,
  max_items? : Int = 64,
) -> Result[ModbusTransaction, ModbusError] {
  if id == "" || !is_valid_unit_id(unit_id) || max_items < 1 {
    return Err(InvalidData)
  }
  Ok({
    id,
    unit_id,
    items: [],
    outcomes: [],
    max_items,
    state: TransactionOpen,
    next_order: 0,
  })
}

///|
pub fn ModbusTransaction::id(self : ModbusTransaction) -> String {
  self.id
}

///|
pub fn ModbusTransaction::unit_id(self : ModbusTransaction) -> Byte {
  self.unit_id
}

///|
pub fn ModbusTransaction::state(self : ModbusTransaction) -> TransactionState {
  self.state
}

///|
pub fn ModbusTransaction::item_count(self : ModbusTransaction) -> Int {
  self.items.length()
}

///|
pub fn ModbusTransaction::outcome_count(self : ModbusTransaction) -> Int {
  self.outcomes.length()
}

///|
pub fn ModbusTransaction::add(
  self : ModbusTransaction,
  request : Frame,
  compensation? : Frame = Frame::new(0, 0, []),
) -> Result[String, ModbusError] {
  if self.state != TransactionOpen || self.items.length() >= self.max_items {
    return Err(Busy)
  }
  if request.unit_id != self.unit_id {
    return Err(UnitMismatch)
  }
  let id = self.id + "-item-" + self.next_order.to_string()
  let item = match
    TransactionItem::new(id, request, self.next_order, compensation~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.items.push(item)
  self.next_order += 1
  Ok(item.id())
}

///|
/// Prepare all requests, rejecting malformed frames before transport I/O.
pub fn ModbusTransaction::prepare(
  self : ModbusTransaction,
) -> Result[Unit, ModbusError] {
  if self.state != TransactionOpen || self.items.length() == 0 {
    return Err(Busy)
  }
  for item in self.items {
    match validate_frame(item.request(), false) {
      Err(error) => {
        self.state = TransactionFailed
        return Err(error)
      }
      Ok(_) => ()
    }
    item.mark(TransactionPrepared)
  }
  self.state = TransactionPrepared
  Ok(())
}

///|
/// Record a successful response for the next prepared item.
pub fn ModbusTransaction::acknowledge(
  self : ModbusTransaction,
  item_id : String,
  response : Frame,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if self.state != TransactionPrepared || timestamp < 0 {
    return Err(Busy)
  }
  for item in self.items {
    if item.id() == item_id {
      if item.state() != TransactionPrepared {
        return Err(Busy)
      }
      if response.unit_id != self.unit_id {
        return Err(UnitMismatch)
      }
      item.mark(TransactionCommitted)
      let outcome = match
        TransactionOutcome::new(
          item_id,
          TransactionCommitted,
          timestamp,
          response~,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.outcomes.push(outcome)
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
/// Mark an item failed and retain the protocol error.
pub fn ModbusTransaction::fail(
  self : ModbusTransaction,
  item_id : String,
  error : ModbusError,
  timestamp : Int,
) -> Result[Unit, ModbusError] {
  if self.state != TransactionPrepared || timestamp < 0 {
    return Err(Busy)
  }
  for item in self.items {
    if item.id() == item_id {
      item.mark(TransactionFailed)
      self.state = TransactionFailed
      let outcome = match
        TransactionOutcome::new(item_id, TransactionFailed, timestamp, error~) {
        Ok(value) => value
        Err(failure) => return Err(failure)
      }
      self.outcomes.push(outcome)
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
/// Commit only when every prepared item has acknowledged successfully.
pub fn ModbusTransaction::commit(
  self : ModbusTransaction,
) -> Result[Unit, ModbusError] {
  if self.state != TransactionPrepared {
    return Err(Busy)
  }
  for item in self.items {
    if item.state() != TransactionCommitted {
      return Err(Incomplete)
    }
  }
  self.state = TransactionCommitted
  Ok(())
}

///|
/// Roll back a prepared or partially committed transaction.
pub fn ModbusTransaction::rollback(
  self : ModbusTransaction,
  timestamp : Int,
) -> Result[Array[Frame], ModbusError] {
  if timestamp < 0 ||
    self.state == TransactionCommitted ||
    self.state == TransactionRolledBack {
    return Err(Busy)
  }
  let compensations : Array[Frame] = []
  for item in self.items {
    if item.state() == TransactionCommitted {
      match item.compensation() {
        Some(frame) => compensations.push(frame)
        None => ()
      }
    }
    item.mark(TransactionRolledBack)
  }
  self.state = TransactionRolledBack
  Ok(compensations)
}

///|
pub fn ModbusTransaction::next_prepared(
  self : ModbusTransaction,
) -> TransactionItem? {
  for item in self.items {
    if item.state() == TransactionPrepared {
      return Some(item)
    }
  }
  None
}

///|
pub fn ModbusTransaction::outcomes(
  self : ModbusTransaction,
) -> Array[TransactionOutcome] {
  self.outcomes
}

///|
pub fn ModbusTransaction::is_successful(self : ModbusTransaction) -> Bool {
  self.state == TransactionCommitted
}

///|
pub fn transaction_state_name(state : TransactionState) -> String {
  match state {
    TransactionOpen => "open"
    TransactionPrepared => "prepared"
    TransactionCommitted => "committed"
    TransactionRolledBack => "rolled-back"
    TransactionFailed => "failed"
  }
}

///|
/// A transaction batch containing several independent units.
pub(all) struct TransactionBatch {
  transactions : Array[ModbusTransaction]
  max_transactions : Int
}

///|
pub fn TransactionBatch::new(
  max_transactions? : Int = 128,
) -> Result[TransactionBatch, ModbusError] {
  if max_transactions < 1 {
    Err(InvalidData)
  } else {
    Ok({ transactions: [], max_transactions })
  }
}

///|
pub fn TransactionBatch::count(self : TransactionBatch) -> Int {
  self.transactions.length()
}

///|
pub fn TransactionBatch::add(
  self : TransactionBatch,
  transaction : ModbusTransaction,
) -> Result[Unit, ModbusError] {
  if self.transactions.length() >= self.max_transactions {
    return Err(CapacityExceeded)
  }
  for existing in self.transactions {
    if existing.id() == transaction.id() {
      return Err(InvalidData)
    }
  }
  self.transactions.push(transaction)
  Ok(())
}

///|
pub fn TransactionBatch::successful(self : TransactionBatch) -> Int {
  let mut count = 0
  for transaction in self.transactions {
    if transaction.is_successful() {
      count += 1
    }
  }
  count
}

///|
pub fn TransactionBatch::failed(self : TransactionBatch) -> Int {
  let mut count = 0
  for transaction in self.transactions {
    if transaction.state() == TransactionFailed {
      count += 1
    }
  }
  count
}
