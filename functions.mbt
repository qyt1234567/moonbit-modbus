///|
fn quantity_bytes(quantity : UInt16) -> Array[Byte] {
  [(quantity >> 8).to_byte(), quantity.to_byte()]
}

///|
/// Build a read-coils request (function 01).
pub fn read_coils(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  if quantity < 1 || quantity > 2000 {
    return Err(InvalidLength)
  }
  Ok({
    unit_id,
    pdu: {
      function: 1,
      data: [(address >> 8).to_byte(), address.to_byte()].add(
        quantity_bytes(quantity),
      ),
    },
  })
}

///|
/// Build a read-input-registers request (function 04).
pub fn read_input_registers(
  unit_id : Byte,
  address : UInt16,
  quantity : UInt16,
) -> Result[Frame, ModbusError] {
  if quantity < 1 || quantity > 125 {
    return Err(InvalidLength)
  }
  Ok({
    unit_id,
    pdu: {
      function: 4,
      data: [(address >> 8).to_byte(), address.to_byte()].add(
        quantity_bytes(quantity),
      ),
    },
  })
}

///|
/// Build a write-multiple-registers request (function 16).
pub fn write_multiple_registers(
  unit_id : Byte,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Frame, ModbusError] {
  if values.length() < 1 || values.length() > 123 {
    return Err(InvalidLength)
  }
  let data : Array[Byte] = [
    (address >> 8).to_byte(),
    address.to_byte(),
    (values.length() >> 8).to_byte(),
    values.length().to_byte(),
    (values.length() * 2).to_byte(),
  ]
  for value in values {
    data.push((value >> 8).to_byte())
    data.push(value.to_byte())
  }
  Ok({ unit_id, pdu: { function: 16, data } })
}

///|
/// Build a standard Modbus exception response.
pub fn exception_response(
  unit_id : Byte,
  function : Byte,
  code : Byte,
) -> Frame {
  { unit_id, pdu: { function: function | 0x80, data: [code] } }
}

///|
/// Whether a PDU is an exception response.
pub fn is_exception(frame : Frame) -> Bool {
  (frame.pdu.function & 0x80) != 0
}

///|
/// Return the function number without the exception bit.
pub fn base_function(frame : Frame) -> Byte {
  frame.pdu.function & 0x7F
}
