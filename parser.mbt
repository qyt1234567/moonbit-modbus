///|
/// A bounded incremental parser for stream transports.
pub struct IncrementalParser {
  mode : Mode
  buffer : Array[Byte]
  max_frame : Int
}

///|
/// Create a stream parser. `max_frame` prevents unbounded input growth.
pub fn IncrementalParser::new(
  mode : Mode,
  max_frame? : Int = 260,
) -> IncrementalParser {
  { mode, buffer: [], max_frame }
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
    return Err(InvalidLength)
  }
  match self.mode {
    Rtu =>
      match decode_rtu(self.buffer) {
        Ok(frame) => {
          self.buffer.clear()
          Ok([frame])
        }
        Err(Incomplete) => Ok([])
        Err(error) => {
          self.buffer.clear()
          Err(error)
        }
      }
    Ascii =>
      match decode_ascii(self.buffer) {
        Ok(frame) => {
          self.buffer.clear()
          Ok([frame])
        }
        Err(Incomplete) => Ok([])
        Err(error) => {
          self.buffer.clear()
          Err(error)
        }
      }
    Tcp =>
      match decode_tcp(self.buffer) {
        Ok((_, frame)) => {
          self.buffer.clear()
          Ok([frame])
        }
        Err(Incomplete) => Ok([])
        Err(error) => {
          self.buffer.clear()
          Err(error)
        }
      }
  }
}

///|
/// Return the number of bytes waiting in the parser.
pub fn IncrementalParser::buffered(self : IncrementalParser) -> Int {
  self.buffer.length()
}
