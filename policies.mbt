///|
/// Return the recommended parser role for a function family.
pub fn recommended_parser_role(function : Byte) -> ParserRole {
  if is_read_function(function) {
    Response
  } else if is_write_function(function) {
    Request
  } else {
    Either
  }
}

///|
pub fn default_frame_limit(mode : Mode) -> Int {
  limits_for(mode).max_adu
}

///|
pub fn default_queue_limit(mode : Mode) -> Int {
  limits_for(mode).max_buffer
}

///|
pub fn accepts_broadcast(mode : Mode) -> Bool {
  mode != Tcp
}

///|
pub fn response_timeout_hint(mode : Mode) -> Int {
  match mode {
    Rtu => 100
    Ascii => 100
    Tcp => 250
  }
}

///|
pub fn retry_limit_for(mode : Mode) -> Int {
  match mode {
    Rtu => 2
    Ascii => 2
    Tcp => 3
  }
}

///|
pub fn should_retry(mode : Mode, error : ModbusError) -> Bool {
  is_retryable(error) && retry_limit_for(mode) > 0
}

///|
pub fn mode_description(mode : Mode) -> String {
  match mode {
    Rtu => "binary serial line with CRC16"
    Ascii => "printable serial line with LRC"
    Tcp => "MBAP-framed network transport"
  }
}

///|
pub fn is_supported_mode(mode : Mode) -> Bool {
  mode == Rtu || mode == Ascii || mode == Tcp
}

///|
pub fn payload_is_bounded(mode : Mode, size : Int) -> Bool {
  size >= 1 && size <= mode_payload_capacity(mode)
}

///|
pub fn frame_budget_available(mode : Mode, frame : Frame, budget : Int) -> Bool {
  budget >= encoded_length(mode, frame)
}
