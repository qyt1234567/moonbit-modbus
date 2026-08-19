///|
/// A Modbus wire mode.
pub(all) enum Mode {
  Rtu
  Ascii
  Tcp
} derive(Debug, Eq)

///|
/// Return the stable display name of a transport mode.
pub fn mode_name(mode : Mode) -> String {
  match mode {
    Rtu => "rtu"
    Ascii => "ascii"
    Tcp => "tcp"
  }
}

///|
/// Standard constructors kept as named entry points for configuration files.
pub fn rtu_mode() -> Mode {
  Rtu
}

///|
pub fn ascii_mode() -> Mode {
  Ascii
}

///|
pub fn tcp_mode() -> Mode {
  Tcp
}

///|
/// The function codes defined by the Modbus application protocol.
pub(all) enum FunctionCode {
  ReadCoils
  ReadDiscreteInputs
  ReadHoldingRegisters
  ReadInputRegisters
  WriteSingleCoil
  WriteSingleRegister
  ReadExceptionStatus
  Diagnostics
  GetCommEventCounter
  GetCommEventLog
  ReportServerId
  WriteMultipleCoils
  WriteMultipleRegisters
  ReportServerIdExtended
  ReadFileRecord
  WriteFileRecord
  MaskWriteRegister
  ReadWriteMultipleRegisters
  ReadFifoQueue
  EncapsulatedInterface
  Unknown(Byte)
} derive(Debug, Eq)

///|
/// Convert a function code byte into the typed function-code vocabulary.
pub fn function_code(value : Byte) -> FunctionCode {
  match value {
    1 => ReadCoils
    2 => ReadDiscreteInputs
    3 => ReadHoldingRegisters
    4 => ReadInputRegisters
    5 => WriteSingleCoil
    6 => WriteSingleRegister
    7 => ReadExceptionStatus
    8 => Diagnostics
    11 => GetCommEventCounter
    12 => GetCommEventLog
    17 => ReportServerId
    15 => WriteMultipleCoils
    16 => WriteMultipleRegisters
    20 => ReadFileRecord
    21 => WriteFileRecord
    22 => MaskWriteRegister
    23 => ReadWriteMultipleRegisters
    24 => ReadFifoQueue
    43 => EncapsulatedInterface
    n => Unknown(n)
  }
}

///|
/// Return the numeric representation of a typed function code.
pub fn FunctionCode::to_byte(code : FunctionCode) -> Byte {
  match code {
    ReadCoils => 1
    ReadDiscreteInputs => 2
    ReadHoldingRegisters => 3
    ReadInputRegisters => 4
    WriteSingleCoil => 5
    WriteSingleRegister => 6
    ReadExceptionStatus => 7
    Diagnostics => 8
    GetCommEventCounter => 11
    GetCommEventLog => 12
    ReportServerId => 17
    WriteMultipleCoils => 15
    WriteMultipleRegisters => 16
    ReportServerIdExtended => 17
    ReadFileRecord => 20
    WriteFileRecord => 21
    MaskWriteRegister => 22
    ReadWriteMultipleRegisters => 23
    ReadFifoQueue => 24
    EncapsulatedInterface => 43
    Unknown(value) => value
  }
}

///|
/// Standard exception codes returned by a Modbus server.
pub(all) enum ExceptionCode {
  IllegalFunction
  IllegalDataAddress
  IllegalDataValue
  ServerDeviceFailure
  Acknowledge
  ServerDeviceBusy
  NegativeAcknowledge
  MemoryParityError
  GatewayPathUnavailable
  GatewayTargetFailedToRespond
  UnknownException(Byte)
} derive(Debug, Eq)

///|
pub fn exception_code(value : Byte) -> ExceptionCode {
  match value {
    1 => IllegalFunction
    2 => IllegalDataAddress
    3 => IllegalDataValue
    4 => ServerDeviceFailure
    5 => Acknowledge
    6 => ServerDeviceBusy
    7 => NegativeAcknowledge
    8 => MemoryParityError
    10 => GatewayPathUnavailable
    11 => GatewayTargetFailedToRespond
    n => UnknownException(n)
  }
}

///|
pub fn ExceptionCode::to_byte(code : ExceptionCode) -> Byte {
  match code {
    IllegalFunction => 1
    IllegalDataAddress => 2
    IllegalDataValue => 3
    ServerDeviceFailure => 4
    Acknowledge => 5
    ServerDeviceBusy => 6
    NegativeAcknowledge => 7
    MemoryParityError => 8
    GatewayPathUnavailable => 10
    GatewayTargetFailedToRespond => 11
    UnknownException(value) => value
  }
}

///|
/// Errors produced by the protocol core and its in-memory services.
pub(all) enum ModbusError {
  Incomplete
  InvalidLength
  InvalidChecksum
  InvalidAscii
  InvalidMbap
  InvalidUnitId
  InvalidFunction
  InvalidAddress
  InvalidQuantity
  InvalidByteCount
  InvalidData
  InvalidTransaction
  Unsupported
  UnitMismatch
  CapacityExceeded
  NoResponse
  Busy
} derive(Debug, Eq)

///|
/// Convert a protocol error to a stable diagnostic name.
pub fn error_name(error : ModbusError) -> String {
  match error {
    Incomplete => "incomplete"
    InvalidLength => "invalid-length"
    InvalidChecksum => "invalid-checksum"
    InvalidAscii => "invalid-ascii"
    InvalidMbap => "invalid-mbap"
    InvalidUnitId => "invalid-unit-id"
    InvalidFunction => "invalid-function"
    InvalidAddress => "invalid-address"
    InvalidQuantity => "invalid-quantity"
    InvalidByteCount => "invalid-byte-count"
    InvalidData => "invalid-data"
    InvalidTransaction => "invalid-transaction"
    Unsupported => "unsupported"
    UnitMismatch => "unit-mismatch"
    CapacityExceeded => "capacity-exceeded"
    NoResponse => "no-response"
    Busy => "busy"
  }
}

///|
/// A Modbus application data unit without transport framing.
pub(all) struct Pdu {
  function : Byte
  data : Array[Byte]
}

///|
pub fn Pdu::new(function : Byte, data : Array[Byte]) -> Pdu {
  { function, data }
}

///|
pub fn Pdu::function_code(self : Pdu) -> FunctionCode {
  function_code(self.function)
}

///|
pub fn Pdu::data_length(self : Pdu) -> Int {
  self.data.length()
}

///|
pub fn Pdu::is_exception(self : Pdu) -> Bool {
  (self.function & 0x80) != 0
}

///|
/// A decoded frame, including the unit identifier.
pub(all) struct Frame {
  unit_id : Byte
  pdu : Pdu
}

///|
pub fn Frame::new(unit_id : Byte, function : Byte, data : Array[Byte]) -> Frame {
  { unit_id, pdu: { function, data } }
}

///|
pub fn Frame::function_code(self : Frame) -> FunctionCode {
  self.pdu.function_code()
}

///|
pub fn Frame::is_exception(self : Frame) -> Bool {
  self.pdu.is_exception()
}

///|
pub fn Frame::data_length(self : Frame) -> Int {
  self.pdu.data_length()
}

///|
/// True when the frame uses the serial-line broadcast address.
pub fn is_broadcast(unit_id : Byte) -> Bool {
  unit_id == 0
}

///|
/// True for a legal serial-line unit identifier, including broadcast.
pub fn is_valid_unit_id(unit_id : Byte, broadcast? : Bool = true) -> Bool {
  (broadcast && unit_id == 0) || (unit_id >= 1 && unit_id <= 247)
}

///|
/// A request/response pair associated with a TCP transaction identifier.
pub(all) struct TransactionFrame {
  transaction_id : UInt16
  request : Frame
  response : Frame?
}

///|
pub fn TransactionFrame::new(
  transaction_id : UInt16,
  request : Frame,
) -> TransactionFrame {
  { transaction_id, request, response: None }
}

///|
pub fn TransactionFrame::complete(
  self : TransactionFrame,
  response : Frame,
) -> TransactionFrame {
  { ..self, response: Some(response) }
}

///|
pub fn TransactionFrame::is_complete(self : TransactionFrame) -> Bool {
  self.response is Some(_)
}

///|
/// A compact description useful for logs and metrics.
pub(all) struct FrameSummary {
  unit_id : Byte
  function : Byte
  data_length : Int
  exception : Bool
}

///|
pub fn summarize(frame : Frame) -> FrameSummary {
  {
    unit_id: frame.unit_id,
    function: frame.pdu.function,
    data_length: frame.pdu.data.length(),
    exception: frame.pdu.is_exception(),
  }
}

///|
/// A raw PDU result that retains whether a response was an exception.
pub(all) enum ResponseValue {
  Normal(Frame)
  Exception(Frame, ExceptionCode)
}

///|
pub fn response_value(frame : Frame) -> ResponseValue {
  if frame.is_exception() && frame.pdu.data.length() == 1 {
    Exception(frame, exception_code(frame.pdu.data[0]))
  } else {
    Normal(frame)
  }
}

///|
/// A small immutable configuration snapshot used by clients and servers.
pub(all) struct ProtocolLimits {
  max_adu : Int
  max_pdu : Int
  max_registers : Int
  max_coils : Int
  max_buffer : Int
}

///|
pub fn default_limits() -> ProtocolLimits {
  {
    max_adu: 260,
    max_pdu: 253,
    max_registers: 125,
    max_coils: 2000,
    max_buffer: 4096,
  }
}

///|
pub fn limits_for(mode : Mode) -> ProtocolLimits {
  match mode {
    Rtu => default_limits()
    Ascii => { ..default_limits(), max_adu: 513 }
    Tcp => { ..default_limits(), max_adu: 260 }
  }
}

///|
/// A request for reading holding registers (function 03).
pub fn read_holding(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Frame {
  {
    unit_id,
    pdu: {
      function: 3,
      data: [
        address.shr(8).to_byte(),
        address.to_byte(),
        quantity.shr(8).to_byte(),
        quantity.to_byte(),
      ],
    },
  }
}

///|
/// Checked variant of `read_holding` for application code.
pub fn read_holding_checked(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else if quantity < 1 || quantity > 125 {
    Err(InvalidQuantity)
  } else if !valid_address_range(address, quantity.to_int()) {
    Err(InvalidAddress)
  } else {
    Ok(read_holding(unit_id, address, quantity))
  }
}

///|
/// A request for writing one holding register (function 06).
pub fn write_single_register(
  unit_id : Byte,
  address : UInt16,
  value : UInt16,
) -> Frame {
  {
    unit_id,
    pdu: {
      function: 6,
      data: [
        address.shr(8).to_byte(),
        address.to_byte(),
        value.shr(8).to_byte(),
        value.to_byte(),
      ],
    },
  }
}

///|
/// Decode a signed 16-bit register using two's-complement representation.
pub fn signed_register(value : UInt16) -> Int {
  let n = value.to_int()
  if n >= 32768 {
    n - 65536
  } else {
    n
  }
}

///|
/// Decode two registers as the raw IEEE-754 single precision words.
pub fn float_words(high : UInt16, low : UInt16) -> UInt64 {
  (high.to_uint64() << 16) + low.to_uint64()
}

///|
/// Decode the data portion of a register-oriented frame without a byte count.
pub fn registers(frame : Frame) -> Result[Array[UInt16], ModbusError] {
  if frame.pdu.data.length() % 2 != 0 {
    return Err(InvalidLength)
  }
  let out : Array[UInt16] = []
  for i in 0..<(frame.pdu.data.length() / 2) {
    out.push(
      frame.pdu.data[i * 2].to_uint16().shl(8) +
      frame.pdu.data[i * 2 + 1].to_uint16(),
    )
  }
  Ok(out)
}
