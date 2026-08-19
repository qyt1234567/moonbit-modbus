///|
/// Convert a byte array to a printable uppercase hexadecimal string.
pub fn bytes_to_hex_string(bytes : Array[Byte]) -> String {
  let builder = StringBuilder()
  for byte in bytes {
    builder.write_char(hex_char(byte >> 4))
    builder.write_char(hex_char(byte & 15))
  }
  builder.to_string()
}

///|
fn hex_char(value : Byte) -> Char {
  if value < 10 {
    (value + 48).to_char()
  } else {
    (value + 55).to_char()
  }
}

///|
/// Convert a string containing hexadecimal digits and optional whitespace to bytes.
pub fn hex_string_to_bytes(text : String) -> Result[Array[Byte], ModbusError] {
  let filtered : Array[Byte] = []
  for character in text {
    if !character.is_ascii_whitespace() {
      filtered.push(character.to_int().to_byte())
    }
  }
  decode_hex(filtered)
}

///|
/// Format a complete frame for logs without exposing transport framing.
pub fn format_frame(frame : Frame) -> String {
  let payload = pdu_bytes(frame)
  "unit=" +
  frame.unit_id.to_string() +
  " function=" +
  function_name(frame.pdu.function) +
  " data=" +
  bytes_to_hex_string(payload)
}

///|
/// Format a frame with its RTU, ASCII, or TCP wire representation.
pub fn format_wire_frame(
  mode : Mode,
  transaction_id : UInt16,
  frame : Frame,
) -> String {
  let bytes = encode_mode(mode, frame)
  let prefix = if mode == Tcp {
    "tx=" + transaction_id.to_string() + " "
  } else {
    ""
  }
  prefix + mode_name(mode) + " " + bytes_to_hex_string(bytes)
}

///|
/// Parse a wire representation in the selected mode.
pub fn parse_wire_frame(
  mode : Mode,
  text : String,
) -> Result[(UInt16, Frame), ModbusError] {
  let bytes = if mode == Ascii {
    let raw : Array[Byte] = []
    for character in text {
      raw.push(character.to_int().to_byte())
    }
    raw
  } else {
    match hex_string_to_bytes(text) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  decode_transaction(mode, bytes)
}

///|
/// A bounded text trace used by CLI tools and embedded diagnostics.
pub struct FrameTextLog {
  entries : Array[String]
  max_entries : Int
}

///|
pub fn FrameTextLog::new(
  max_entries? : Int = 256,
) -> Result[FrameTextLog, ModbusError] {
  if max_entries < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ entries: [], max_entries })
  }
}

///|
pub fn FrameTextLog::push(self : FrameTextLog, line : String) -> Unit {
  if self.entries.length() >= self.max_entries {
    discard_string_prefix(self.entries, 1)
  }
  self.entries.push(line)
}

///|
pub fn FrameTextLog::record(
  self : FrameTextLog,
  direction : String,
  frame : Frame,
) -> Unit {
  self.push(direction + " " + format_frame(frame))
}

///|
pub fn FrameTextLog::record_wire(
  self : FrameTextLog,
  direction : String,
  mode : Mode,
  transaction_id : UInt16,
  frame : Frame,
) -> Unit {
  self.push(direction + " " + format_wire_frame(mode, transaction_id, frame))
}

///|
pub fn FrameTextLog::length(self : FrameTextLog) -> Int {
  self.entries.length()
}

///|
pub fn FrameTextLog::lines(self : FrameTextLog) -> Array[String] {
  let out : Array[String] = []
  for line in self.entries {
    out.push(line)
  }
  out
}

///|
pub fn FrameTextLog::clear(self : FrameTextLog) -> Unit {
  self.entries.clear()
}

///|
fn discard_string_prefix(values : Array[String], count : Int) -> Unit {
  let retained : Array[String] = []
  for index in count..<values.length() {
    retained.push(values[index])
  }
  values.clear()
  for value in retained {
    values.push(value)
  }
}

///|
/// Produce a one-line protocol error for a CLI diagnostic.
pub fn format_error(error : ModbusError) -> String {
  "modbus error: " + error_name(error)
}
