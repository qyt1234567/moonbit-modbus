///|
/// Named transport choices used by adapters.
pub(all) enum TransportKind {
  SerialRtu
  SerialAscii
  ModbusTcp
} derive(Debug, Eq)

///|
pub fn transport_kind_mode(kind : TransportKind) -> Mode {
  match kind {
    SerialRtu => Rtu
    SerialAscii => Ascii
    ModbusTcp => Tcp
  }
}

///|
pub fn transport_kind_name(kind : TransportKind) -> String {
  match kind {
    SerialRtu => "serial-rtu"
    SerialAscii => "serial-ascii"
    ModbusTcp => "modbus-tcp"
  }
}

///|
/// An encoded ADU that can be handed to a socket or serial adapter.
pub(all) struct EncodedAdu {
  mode : Mode
  transaction_id : UInt16
  bytes : Array[Byte]
}

///|
pub fn EncodedAdu::new(
  mode : Mode,
  transaction_id : UInt16,
  frame : Frame,
) -> Result[EncodedAdu, ModbusError] {
  match try_encode_mode(mode, transaction_id, frame) {
    Ok(bytes) => Ok({ mode, transaction_id, bytes })
    Err(error) => Err(error)
  }
}

///|
pub fn EncodedAdu::bytes(self : EncodedAdu) -> Array[Byte] {
  copy_bytes(self.bytes)
}

///|
pub fn EncodedAdu::mode(self : EncodedAdu) -> Mode {
  self.mode
}

///|
pub fn EncodedAdu::transaction_id(self : EncodedAdu) -> UInt16 {
  self.transaction_id
}

///|
pub fn EncodedAdu::decode(self : EncodedAdu) -> Result[Frame, ModbusError] {
  match decode_transaction(self.mode, self.bytes) {
    Ok((transaction_id, frame)) =>
      if self.mode == Tcp && transaction_id != self.transaction_id {
        Err(InvalidTransaction)
      } else {
        Ok(frame)
      }
    Err(error) => Err(error)
  }
}

///|
/// A transport-neutral request envelope.
pub(all) struct ExchangeEnvelope {
  source : String
  destination : String
  adu : EncodedAdu
}

///|
pub fn ExchangeEnvelope::new(
  source : String,
  destination : String,
  adu : EncodedAdu,
) -> ExchangeEnvelope {
  { source, destination, adu }
}

///|
pub fn ExchangeEnvelope::size(self : ExchangeEnvelope) -> Int {
  self.adu.bytes.length()
}

///|
/// A deterministic in-memory transport used by tests, demos, and simulators.
pub struct VirtualLink {
  mode : Mode
  max_queue : Int
  master_to_device : Array[Array[Byte]]
  device_to_master : Array[Array[Byte]]
  mut sent : Int
  mut received : Int
  mut dropped : Int
}

///|
pub fn VirtualLink::new(
  mode : Mode,
  max_queue? : Int = 64,
) -> Result[VirtualLink, ModbusError] {
  if max_queue < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({
      mode,
      max_queue,
      master_to_device: [],
      device_to_master: [],
      sent: 0,
      received: 0,
      dropped: 0,
    })
  }
}

///|
pub fn VirtualLink::mode(self : VirtualLink) -> Mode {
  self.mode
}

///|
pub fn VirtualLink::send_request(
  self : VirtualLink,
  transaction_id : UInt16,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  let adu = match EncodedAdu::new(self.mode, transaction_id, frame) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if self.master_to_device.length() >= self.max_queue {
    self.dropped += 1
    Err(Busy)
  } else {
    self.master_to_device.push(adu.bytes())
    self.sent += 1
    Ok(())
  }
}

///|
pub fn VirtualLink::receive_request(
  self : VirtualLink,
) -> Result[Frame, ModbusError] {
  match take_queue_head(self.master_to_device) {
    None => Err(NoResponse)
    Some(bytes) =>
      match decode_mode(self.mode, bytes) {
        Ok(frame) => Ok(frame)
        Err(error) => Err(error)
      }
  }
}

///|
pub fn VirtualLink::send_response(
  self : VirtualLink,
  transaction_id : UInt16,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  let adu = match EncodedAdu::new(self.mode, transaction_id, frame) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if self.device_to_master.length() >= self.max_queue {
    self.dropped += 1
    Err(Busy)
  } else {
    self.device_to_master.push(adu.bytes())
    Ok(())
  }
}

///|
pub fn VirtualLink::receive_response(
  self : VirtualLink,
) -> Result[Array[Byte], ModbusError] {
  match take_queue_head(self.device_to_master) {
    None => Err(NoResponse)
    Some(bytes) => {
      self.received += 1
      Ok(bytes)
    }
  }
}

///|
/// Execute one request against a device and enqueue its response.
pub fn VirtualLink::round_trip(
  self : VirtualLink,
  device : Device,
  transaction_id : UInt16,
  request : Frame,
) -> Result[DeviceResponse, ModbusError] {
  match device.serve(request) {
    Err(error) => Err(error)
    Ok(NoReply) => Ok(NoReply)
    Ok(Reply(response)) =>
      match self.send_response(transaction_id, response) {
        Ok(_) => Ok(Reply(response))
        Err(error) => Err(error)
      }
  }
}

///|
pub fn VirtualLink::sent_count(self : VirtualLink) -> Int {
  self.sent
}

///|
pub fn VirtualLink::received_count(self : VirtualLink) -> Int {
  self.received
}

///|
pub fn VirtualLink::dropped_count(self : VirtualLink) -> Int {
  self.dropped
}

///|
pub fn VirtualLink::queued_requests(self : VirtualLink) -> Int {
  self.master_to_device.length()
}

///|
pub fn VirtualLink::queued_responses(self : VirtualLink) -> Int {
  self.device_to_master.length()
}

///|
pub fn VirtualLink::clear(self : VirtualLink) -> Unit {
  self.master_to_device.clear()
  self.device_to_master.clear()
}

///|
fn take_queue_head(queue : Array[Array[Byte]]) -> Array[Byte]? {
  if queue.length() == 0 {
    None
  } else {
    let head = queue[0]
    discard_byte_queue_prefix(queue, 1)
    Some(head)
  }
}

///|
fn discard_byte_queue_prefix(queue : Array[Array[Byte]], count : Int) -> Unit {
  let remaining : Array[Array[Byte]] = []
  for index in count..<queue.length() {
    remaining.push(queue[index])
  }
  queue.clear()
  for item in remaining {
    queue.push(item)
  }
}

///|
/// A transport capability report for startup diagnostics.
pub(all) struct TransportCapabilities {
  mode : Mode
  max_adu : Int
  supports_broadcast : Bool
  preserves_transaction_id : Bool
}

///|
pub fn capabilities(mode : Mode) -> TransportCapabilities {
  {
    mode,
    max_adu: limits_for(mode).max_adu,
    supports_broadcast: mode != Tcp,
    preserves_transaction_id: mode == Tcp,
  }
}

///|
pub fn transport_is_serial(mode : Mode) -> Bool {
  mode == Rtu || mode == Ascii
}

///|
pub fn transport_is_network(mode : Mode) -> Bool {
  mode == Tcp
}
