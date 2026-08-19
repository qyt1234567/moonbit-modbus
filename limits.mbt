///|
/// Return whether a frame can be represented by a mode's ADU limit.
pub fn fits_mode_limit(mode : Mode, frame : Frame) -> Bool {
  encoded_length(mode, frame) <= limits_for(mode).max_adu
}

///|
/// Return the number of data bytes available after transport framing.
pub fn mode_payload_capacity(mode : Mode) -> Int {
  match mode {
    Rtu => limits_for(mode).max_adu - 4
    Ascii => (limits_for(mode).max_adu - 7) / 2 - 2
    Tcp => limits_for(mode).max_adu - 8
  }
}

///|
pub fn validate_mode_payload(
  mode : Mode,
  data_length : Int,
) -> Result[Unit, ModbusError] {
  if data_length < 1 || data_length > mode_payload_capacity(mode) {
    Err(InvalidLength)
  } else {
    Ok(())
  }
}

///|
/// Return a conservative maximum request size for a function and mode.
pub fn max_request_adu(mode : Mode, function : Byte) -> Int {
  let payload = match function {
    1 | 2 => 4
    3 | 4 => 4
    5 | 6 => 4
    15 => 253
    16 => 251
    20 => 246
    21 => 253
    22 => 6
    23 => 251
    43 => 253
    _ => 252
  }
  match mode {
    Rtu => payload + 4
    Ascii => 7 + (payload + 2) * 2
    Tcp => payload + 8
  }
}

///|
/// Calculate the number of frames needed for a logical register read.
pub fn frame_count_for_registers(quantity : Int) -> Result[Int, ModbusError] {
  if quantity < 1 {
    Err(InvalidQuantity)
  } else {
    Ok((quantity + 124) / 125)
  }
}

///|
/// Calculate the number of frames needed for a logical coil read.
pub fn frame_count_for_coils(quantity : Int) -> Result[Int, ModbusError] {
  if quantity < 1 {
    Err(InvalidQuantity)
  } else {
    Ok((quantity + 1999) / 2000)
  }
}

///|
/// Check whether a write payload is legal before allocating its data array.
pub fn validate_write_shape(
  function : Byte,
  quantity : Int,
) -> Result[Unit, ModbusError] {
  let limit = write_quantity_limit(function)
  if limit == 0 {
    Err(InvalidFunction)
  } else if quantity < 1 || quantity > limit {
    Err(InvalidQuantity)
  } else {
    Ok(())
  }
}

///|
/// Check that an entire sequence stays below a caller's queue budget.
pub fn fits_queue_budget(
  frames : Array[Frame],
  mode : Mode,
  budget : Int,
) -> Bool {
  if budget < 0 {
    return false
  }
  let mut used = 0
  for frame in frames {
    used += encoded_length(mode, frame)
  }
  used <= budget
}
