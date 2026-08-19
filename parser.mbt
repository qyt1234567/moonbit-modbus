///|
/// The side of a stream that an incremental parser is consuming.
pub(all) enum ParserRole {
  Request
  Response
  Either
} derive(Debug, Eq)

///|
/// A bounded incremental parser for stream transports.
pub struct IncrementalParser {
  mode : Mode
  role : ParserRole
  buffer : Array[Byte]
  mut max_frame : Int
  mut frames_seen : Int
  mut errors_seen : Int
}

///|
/// Create a stream parser. `max_frame` prevents unbounded input growth.
pub fn IncrementalParser::new(
  mode : Mode,
  max_frame? : Int = 260,
  role? : ParserRole = Either,
) -> IncrementalParser {
  let minimum = minimum_frame_length(mode)
  let bounded = if max_frame < minimum { minimum } else { max_frame }
  { mode, role, buffer: [], max_frame: bounded, frames_seen: 0, errors_seen: 0 }
}

///|
pub fn IncrementalParser::mode(self : IncrementalParser) -> Mode {
  self.mode
}

///|
pub fn IncrementalParser::role(self : IncrementalParser) -> ParserRole {
  self.role
}

///|
pub fn IncrementalParser::max_frame(self : IncrementalParser) -> Int {
  self.max_frame
}

///|
/// Feed bytes and return every complete frame currently available.
pub fn IncrementalParser::feed(
  self : IncrementalParser,
  input : Array[Byte],
) -> Result[Array[Frame], ModbusError] {
  for byte in input {
    self.buffer.push(byte)
  }
  if self.buffer.length() > self.max_frame {
    self.buffer.clear()
    self.errors_seen += 1
    return Err(InvalidLength)
  }
  let out : Array[Frame] = []
  let mut keep_going = true
  while keep_going && self.buffer.length() > 0 {
    match self.next_frame_length() {
      None => keep_going = false
      Some(0) => keep_going = false
      Some(length) => {
        if length > self.max_frame {
          self.buffer.clear()
          self.errors_seen += 1
          return Err(InvalidLength)
        }
        if self.buffer.length() < length {
          keep_going = false
        } else {
          let candidate = match copy_range(self.buffer, 0, length) {
            Ok(value) => value
            Err(error) => {
              self.buffer.clear()
              self.errors_seen += 1
              return Err(error)
            }
          }
          match decode_mode(self.mode, candidate) {
            Ok(frame) => {
              discard_prefix(self.buffer, length)
              out.push(frame)
              self.frames_seen += 1
            }
            Err(Incomplete) => keep_going = false
            Err(error) => {
              self.buffer.clear()
              self.errors_seen += 1
              return Err(error)
            }
          }
        }
      }
    }
  }
  Ok(out)
}

///|
/// Feed a single byte without allocating an input array at the call site.
pub fn IncrementalParser::feed_byte(
  self : IncrementalParser,
  byte : Byte,
) -> Result[Array[Frame], ModbusError] {
  self.feed([byte])
}

///|
/// Finish a serial frame at an externally supplied RTU silent interval.
pub fn IncrementalParser::finish(
  self : IncrementalParser,
) -> Result[Frame, ModbusError] {
  if self.buffer.length() == 0 {
    return Err(Incomplete)
  }
  let frame = decode_mode(self.mode, self.buffer)
  self.buffer.clear()
  match frame {
    Ok(value) => {
      self.frames_seen += 1
      Ok(value)
    }
    Err(error) => {
      self.errors_seen += 1
      Err(error)
    }
  }
}

///|
/// Discard buffered bytes after a transport reset.
pub fn IncrementalParser::reset(self : IncrementalParser) -> Unit {
  self.buffer.clear()
}

///|
/// Return the number of bytes waiting in the parser.
pub fn IncrementalParser::buffered(self : IncrementalParser) -> Int {
  self.buffer.length()
}

///|
pub fn IncrementalParser::frames_seen(self : IncrementalParser) -> Int {
  self.frames_seen
}

///|
pub fn IncrementalParser::errors_seen(self : IncrementalParser) -> Int {
  self.errors_seen
}

///|
/// Take the current buffered bytes and reset the parser.
pub fn IncrementalParser::take_buffer(self : IncrementalParser) -> Array[Byte] {
  let out = copy_bytes(self.buffer)
  self.buffer.clear()
  out
}

///|
/// Change the maximum frame size for a parser that is already in use.
pub fn IncrementalParser::set_max_frame(
  self : IncrementalParser,
  max_frame : Int,
) -> Result[Unit, ModbusError] {
  if max_frame < minimum_frame_length(self.mode) {
    Err(InvalidLength)
  } else if self.buffer.length() > max_frame {
    Err(CapacityExceeded)
  } else {
    self.max_frame = max_frame
    Ok(())
  }
}

///|
fn IncrementalParser::next_frame_length(self : IncrementalParser) -> Int? {
  match self.mode {
    Tcp =>
      match expected_tcp_length(self.buffer) {
        Ok(length) => Some(length)
        Err(Incomplete) => None
        Err(_) => Some(self.max_frame + 1)
      }
    Ascii => ascii_stream_length(self.buffer)
    Rtu => rtu_stream_length(self.buffer, self.role)
  }
}

///|
fn discard_prefix(buffer : Array[Byte], length : Int) -> Unit {
  if length >= buffer.length() {
    buffer.clear()
  } else {
    let tail : Array[Byte] = []
    for index in length..<buffer.length() {
      tail.push(buffer[index])
    }
    buffer.clear()
    for byte in tail {
      buffer.push(byte)
    }
  }
}

///|
fn ascii_stream_length(buffer : Array[Byte]) -> Int? {
  let mut start = 0
  while start < buffer.length() && buffer[start] != 58 {
    start += 1
  }
  if start > 0 {
    discard_prefix(buffer, start)
  }
  if buffer.length() < 7 {
    return None
  }
  let mut index = 1
  while index + 1 < buffer.length() {
    if buffer[index] == 13 && buffer[index + 1] == 10 {
      return Some(index + 2)
    }
    index += 1
  }
  None
}

///|
/// Infer the RTU frame size from the function shape and parser role.
fn rtu_stream_length(buffer : Array[Byte], role : ParserRole) -> Int? {
  if buffer.length() < 2 {
    return None
  }
  let function = buffer[1]
  if (function & 0x80) != 0 {
    return if buffer.length() >= 5 { Some(5) } else { None }
  }
  match function_code(function) {
    ReadCoils
    | ReadDiscreteInputs
    | ReadHoldingRegisters
    | ReadInputRegisters =>
      match role {
        Request => fixed_request_length(buffer)
        Response => byte_count_response_length(buffer)
        Either => either_read_length(buffer)
      }
    WriteSingleCoil | WriteSingleRegister | MaskWriteRegister =>
      if buffer.length() >= 8 {
        Some(8)
      } else {
        None
      }
    ReadExceptionStatus => if buffer.length() >= 4 { Some(4) } else { None }
    GetCommEventCounter => if buffer.length() >= 8 { Some(8) } else { None }
    GetCommEventLog => if buffer.length() >= 4 { Some(4) } else { None }
    ReportServerId =>
      match role {
        Request => if buffer.length() >= 4 { Some(4) } else { None }
        _ => byte_count_response_length(buffer)
      }
    WriteMultipleCoils | WriteMultipleRegisters =>
      match role {
        Response => if buffer.length() >= 8 { Some(8) } else { None }
        _ => variable_write_length(buffer)
      }
    ReadWriteMultipleRegisters =>
      match role {
        Request => variable_read_write_request_length(buffer)
        Response => byte_count_response_length(buffer)
        Either => variable_read_write_request_length(buffer)
      }
    ReadFifoQueue =>
      if buffer.length() >= 4 {
        let count = (buffer[2].to_int() << 8) | buffer[3].to_int()
        Some(6 + count)
      } else {
        None
      }
    Diagnostics | ReadFileRecord | WriteFileRecord | EncapsulatedInterface =>
      None
    Unknown(_) => None
    _ => if buffer.length() >= 4 { Some(4) } else { None }
  }
}

///|
fn fixed_request_length(buffer : Array[Byte]) -> Int? {
  if buffer.length() >= 8 {
    Some(8)
  } else {
    None
  }
}

///|
fn byte_count_response_length(buffer : Array[Byte]) -> Int? {
  if buffer.length() < 3 {
    None
  } else {
    Some(5 + buffer[2].to_int())
  }
}

///|
fn either_read_length(buffer : Array[Byte]) -> Int? {
  if buffer.length() < 3 {
    return None
  }
  let response_length = 5 + buffer[2].to_int()
  if buffer[2] > 0 {
    Some(response_length)
  } else if buffer.length() >= 8 {
    Some(8)
  } else {
    None
  }
}

///|
fn variable_write_length(buffer : Array[Byte]) -> Int? {
  if buffer.length() < 7 {
    None
  } else {
    Some(9 + buffer[6].to_int())
  }
}

///|
fn variable_read_write_request_length(buffer : Array[Byte]) -> Int? {
  if buffer.length() < 9 {
    None
  } else {
    Some(11 + buffer[8].to_int())
  }
}

///|
/// Return the number of bytes currently held across parser metrics.
pub fn parser_load(parser : IncrementalParser) -> Int {
  parser.buffered() + parser.frames_seen() + parser.errors_seen()
}
