///|
/// A bounded ordered collection of frames for gateways and batch adapters.
pub struct FrameSequence {
  frames : Array[Frame]
  max_frames : Int
}

///|
pub fn FrameSequence::new(
  max_frames? : Int = 1024,
) -> Result[FrameSequence, ModbusError] {
  if max_frames < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ frames: [], max_frames })
  }
}

///|
pub fn FrameSequence::push(
  self : FrameSequence,
  frame : Frame,
) -> Result[Unit, ModbusError] {
  if self.frames.length() >= self.max_frames {
    Err(CapacityExceeded)
  } else {
    self.frames.push(frame)
    Ok(())
  }
}

///|
pub fn FrameSequence::length(self : FrameSequence) -> Int {
  self.frames.length()
}

///|
pub fn FrameSequence::get(
  self : FrameSequence,
  index : Int,
) -> Result[Frame, ModbusError] {
  if index < 0 || index >= self.frames.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.frames[index])
  }
}

///|
pub fn FrameSequence::snapshot(self : FrameSequence) -> Array[Frame] {
  let out : Array[Frame] = []
  for frame in self.frames {
    out.push(frame)
  }
  out
}

///|
pub fn FrameSequence::validate(
  self : FrameSequence,
  allow_broadcast : Bool,
) -> Result[Unit, ModbusError] {
  for frame in self.frames {
    match validate_frame(frame, allow_broadcast) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
pub fn FrameSequence::encoded_bytes(self : FrameSequence, mode : Mode) -> Int {
  let mut total = 0
  for frame in self.frames {
    total += encoded_length(mode, frame)
  }
  total
}

///|
pub fn FrameSequence::filter_function(
  self : FrameSequence,
  function : Byte,
) -> Array[Frame] {
  let out : Array[Frame] = []
  for frame in self.frames {
    if ordinary_function(frame.pdu.function) == function {
      out.push(frame)
    }
  }
  out
}

///|
pub fn FrameSequence::filter_unit(
  self : FrameSequence,
  unit_id : Byte,
) -> Array[Frame] {
  let out : Array[Frame] = []
  for frame in self.frames {
    if frame.unit_id == unit_id {
      out.push(frame)
    }
  }
  out
}

///|
/// Compare frames at the logical PDU level.
pub fn frames_equal(left : Frame, right : Frame) -> Bool {
  left.unit_id == right.unit_id &&
  left.pdu.function == right.pdu.function &&
  left.pdu.data == right.pdu.data
}

///|
pub fn pdus_equal(left : Pdu, right : Pdu) -> Bool {
  left.function == right.function && left.data == right.data
}

///|
pub fn frame_data_copy(frame : Frame) -> Array[Byte] {
  copy_bytes(frame.pdu.data)
}

///|
pub fn frame_with_data_copy(frame : Frame, data : Array[Byte]) -> Frame {
  {
    unit_id: frame.unit_id,
    pdu: { function: frame.pdu.function, data: copy_bytes(data) },
  }
}

///|
/// Add a signed address offset while preserving 16-bit bounds.
pub fn offset_frame_address(
  frame : Frame,
  delta : Int,
) -> Result[Frame, ModbusError] {
  if frame.pdu.data.length() < 2 {
    return Err(InvalidLength)
  }
  let address = ((frame.pdu.data[0].to_uint16() << 8) |
  frame.pdu.data[1].to_uint16()).to_int()
  let next = address + delta
  if next < 0 || next > 65535 {
    return Err(InvalidAddress)
  }
  let data = copy_bytes(frame.pdu.data)
  data[0] = (next / 256).to_byte()
  data[1] = next.to_byte()
  Ok(frame_with_data_copy(frame, data))
}

///|
pub fn replace_frame_unit(
  frame : Frame,
  unit_id : Byte,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({
      unit_id,
      pdu: { function: frame.pdu.function, data: copy_bytes(frame.pdu.data) },
    })
  }
}

///|
pub fn safe_byte_at(
  bytes : Array[Byte],
  index : Int,
) -> Result[Byte, ModbusError] {
  if index < 0 || index >= bytes.length() {
    Err(Incomplete)
  } else {
    Ok(bytes[index])
  }
}

///|
pub fn is_read_function(function : Byte) -> Bool {
  function == 1 ||
  function == 2 ||
  function == 3 ||
  function == 4 ||
  function == 7 ||
  function == 8 ||
  function == 11 ||
  function == 12 ||
  function == 17 ||
  function == 20 ||
  function == 24 ||
  function == 43
}

///|
pub fn is_write_function(function : Byte) -> Bool {
  function == 5 ||
  function == 6 ||
  function == 15 ||
  function == 16 ||
  function == 21 ||
  function == 22 ||
  function == 23
}

///|
pub fn response_payload_length(frame : Frame) -> Int {
  frame.pdu.data.length()
}

///|
pub fn frame_is_empty(frame : Frame) -> Bool {
  frame.pdu.data.length() == 0
}

///|
pub fn frame_is_valid(frame : Frame) -> Bool {
  validate_frame(frame, true) is Ok(_)
}

///|
pub fn error_or_unit(result : Result[Unit, ModbusError]) -> String {
  match result {
    Ok(_) => "ok"
    Err(error) => error_name(error)
  }
}
