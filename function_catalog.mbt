///|
/// Metadata used by configuration UIs and validation tools.
pub(all) struct FunctionDescriptor {
  function : Byte
  name : String
  request_min : Int
  request_max : Int
  response_variable : Bool
  writable : Bool
  description : String
}

///|
fn descriptor(
  function : Byte,
  name : String,
  request_min : Int,
  request_max : Int,
  response_variable : Bool,
  writable : Bool,
  description : String,
) -> FunctionDescriptor {
  {
    function,
    name,
    request_min,
    request_max,
    response_variable,
    writable,
    description,
  }
}

///|
pub fn function_descriptor(function : Byte) -> FunctionDescriptor? {
  match function_code(function) {
    ReadCoils =>
      Some(
        descriptor(
          1, "read-coils", 4, 4, true, false, "Read packed coil states.",
        ),
      )
    ReadDiscreteInputs =>
      Some(
        descriptor(
          2, "read-discrete-inputs", 4, 4, true, false, "Read packed discrete inputs.",
        ),
      )
    ReadHoldingRegisters =>
      Some(
        descriptor(
          3, "read-holding-registers", 4, 4, true, false, "Read holding registers.",
        ),
      )
    ReadInputRegisters =>
      Some(
        descriptor(
          4, "read-input-registers", 4, 4, true, false, "Read read-only input registers.",
        ),
      )
    WriteSingleCoil =>
      Some(
        descriptor(5, "write-single-coil", 4, 4, false, true, "Write one coil."),
      )
    WriteSingleRegister =>
      Some(
        descriptor(
          6, "write-single-register", 4, 4, false, true, "Write one holding register.",
        ),
      )
    ReadExceptionStatus =>
      Some(
        descriptor(
          7, "read-exception-status", 0, 0, false, false, "Read the device exception status.",
        ),
      )
    Diagnostics =>
      Some(
        descriptor(
          8, "diagnostics", 2, 252, true, false, "Run a diagnostics subfunction.",
        ),
      )
    GetCommEventCounter =>
      Some(
        descriptor(
          11, "get-comm-event-counter", 0, 0, false, false, "Read communication event counters.",
        ),
      )
    GetCommEventLog =>
      Some(
        descriptor(
          12, "get-comm-event-log", 0, 0, true, false, "Read the communication event log.",
        ),
      )
    ReportServerId =>
      Some(
        descriptor(
          17, "report-server-id", 0, 0, true, false, "Read server identification bytes.",
        ),
      )
    WriteMultipleCoils =>
      Some(
        descriptor(
          15, "write-multiple-coils", 6, 253, false, true, "Write packed coil states.",
        ),
      )
    WriteMultipleRegisters =>
      Some(
        descriptor(
          16, "write-multiple-registers", 6, 251, false, true, "Write a register block.",
        ),
      )
    ReadFileRecord =>
      Some(
        descriptor(
          20, "read-file-record", 8, 246, true, false, "Read file records.",
        ),
      )
    WriteFileRecord =>
      Some(
        descriptor(
          21, "write-file-record", 9, 253, false, true, "Write file records.",
        ),
      )
    MaskWriteRegister =>
      Some(
        descriptor(
          22, "mask-write-register", 6, 6, false, true, "Apply an AND/OR mask.",
        ),
      )
    ReadWriteMultipleRegisters =>
      Some(
        descriptor(
          23, "read-write-multiple-registers", 9, 251, true, true, "Write then read register blocks.",
        ),
      )
    ReadFifoQueue =>
      Some(
        descriptor(
          24, "read-fifo-queue", 2, 2, true, false, "Read a FIFO queue.",
        ),
      )
    EncapsulatedInterface =>
      Some(
        descriptor(
          43, "encapsulated-interface", 1, 253, true, false, "Access a MEI subprotocol.",
        ),
      )
    _ => None
  }
}

///|
/// Return every descriptor in numeric order.
pub fn function_catalog() -> Array[FunctionDescriptor] {
  let out : Array[FunctionDescriptor] = []
  let codes : Array[Byte] = [
    1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 15, 16, 17, 20, 21, 22, 23, 24, 43,
  ]
  for code in codes {
    match function_descriptor(code) {
      Some(value) => out.push(value)
      None => ()
    }
  }
  out
}

///|
pub fn FunctionDescriptor::supports_request(
  self : FunctionDescriptor,
  length : Int,
) -> Bool {
  length >= self.request_min && length <= self.request_max
}

///|
pub fn FunctionDescriptor::is_write(self : FunctionDescriptor) -> Bool {
  self.writable
}

///|
pub fn FunctionDescriptor::name(self : FunctionDescriptor) -> String {
  self.name
}

///|
pub fn FunctionDescriptor::function(self : FunctionDescriptor) -> Byte {
  self.function
}

///|
pub fn FunctionDescriptor::description(self : FunctionDescriptor) -> String {
  self.description
}

///|
/// Validate a request against the catalog before invoking a builder.
pub fn validate_catalog_request(frame : Frame) -> Result[Unit, ModbusError] {
  let descriptor = match function_descriptor(frame.pdu.function) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  if descriptor.supports_request(frame.pdu.data.length()) {
    validate_pdu(frame.pdu)
  } else {
    Err(InvalidLength)
  }
}

///|
/// Return the names of all writable functions.
pub fn writable_function_names() -> Array[String] {
  let out : Array[String] = []
  for descriptor in function_catalog() {
    if descriptor.writable {
      out.push(descriptor.name)
    }
  }
  out
}

///|
/// Return the names of all functions whose response contains a byte count.
pub fn variable_response_function_names() -> Array[String] {
  let out : Array[String] = []
  for descriptor in function_catalog() {
    if descriptor.response_variable {
      out.push(descriptor.name)
    }
  }
  out
}
