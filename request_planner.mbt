///|
/// A range request planner that splits large logical reads into legal PDUs.
pub(all) struct PlannedRequest {
  id : Int
  frame : Frame
  address : AddressRange
}

///|
pub fn plan_read_registers(
  unit_id : Byte,
  address : UInt16,
  quantity : Int,
  function? : Byte = 3,
) -> Result[Array[PlannedRequest], ModbusError] {
  if function != 3 && function != 4 {
    return Err(InvalidFunction)
  }
  let range = match AddressRange::new(address, quantity) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let segments = match range.split(125) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let out : Array[PlannedRequest] = []
  for index, segment in segments {
    let request = if function == 3 {
      read_holding_registers(unit_id, segment.start, segment.length.to_uint16())
    } else {
      read_input_registers(unit_id, segment.start, segment.length.to_uint16())
    }
    match request {
      Ok(frame) => out.push({ id: index, frame, address: segment })
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
pub fn plan_read_coils(
  unit_id : Byte,
  address : UInt16,
  quantity : Int,
  discrete? : Bool = false,
) -> Result[Array[PlannedRequest], ModbusError] {
  let range = match AddressRange::new(address, quantity) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let segments = match range.split(2000) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let out : Array[PlannedRequest] = []
  for index, segment in segments {
    let request = if discrete {
      read_discrete_inputs(unit_id, segment.start, segment.length.to_uint16())
    } else {
      read_coils(unit_id, segment.start, segment.length.to_uint16())
    }
    match request {
      Ok(frame) => out.push({ id: index, frame, address: segment })
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
/// Plan a write block, respecting the protocol's maximum register quantity.
pub fn plan_write_registers(
  unit_id : Byte,
  address : UInt16,
  values : Array[UInt16],
) -> Result[Array[PlannedRequest], ModbusError] {
  if values.length() == 0 {
    return Err(InvalidQuantity)
  }
  let range = match AddressRange::new(address, values.length()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let out : Array[PlannedRequest] = []
  let mut offset = 0
  let mut id = 0
  while offset < values.length() {
    let length = if values.length() - offset > 123 {
      123
    } else {
      values.length() - offset
    }
    let chunk : Array[UInt16] = []
    for index in offset..<(offset + length) {
      chunk.push(values[index])
    }
    let current_address = (address.to_int() + offset).to_uint16()
    match write_multiple_registers(unit_id, current_address, chunk) {
      Ok(frame) => {
        let segment = range.slice(offset, length).unwrap()
        out.push({ id, frame, address: segment })
      }
      Err(error) => return Err(error)
    }
    offset += length
    id += 1
  }
  Ok(out)
}

///|
/// A request plan summary used to size queues before dispatch.
pub(all) struct PlanSummary {
  requests : Int
  total_registers : Int
  total_coils : Int
  total_bytes : Int
}

///|
pub fn summarize_plan(items : Array[PlannedRequest]) -> PlanSummary {
  let mut registers = 0
  let mut coils = 0
  let mut bytes = 0
  for item in items {
    let function = item.frame.pdu.function
    if function == 1 || function == 2 {
      coils += item.address.length
    } else {
      registers += item.address.length
    }
    bytes += item.frame.pdu.data.length()
  }
  {
    requests: items.length(),
    total_registers: registers,
    total_coils: coils,
    total_bytes: bytes,
  }
}

///|
/// Validate that planned ranges are ordered and non-overlapping.
pub fn validate_plan_order(
  items : Array[PlannedRequest],
) -> Result[Unit, ModbusError] {
  for index in 1..<items.length() {
    let previous = items[index - 1]
    let current = items[index]
    if current.id <= previous.id || previous.address.overlaps(current.address) {
      return Err(InvalidData)
    }
  }
  Ok(())
}
