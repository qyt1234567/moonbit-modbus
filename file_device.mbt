///|
fn Device::handle_read_file_record(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let references = match parse_file_references(request.pdu.data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let payload : Array[Byte] = [0]
  let mut total = 0
  for reference in references {
    let values = match self.file_store.get(reference) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let sub_length = 1 + values.length() * 2
    total += sub_length
    if total > 252 {
      return Err(InvalidLength)
    }
    payload.push(reference.reference_type)
    for value in values {
      payload.push((value >> 8).to_byte())
      payload.push(value.to_byte())
    }
  }
  payload[0] = total.to_byte()
  Ok(response_frame(request, payload))
}

///|
fn Device::handle_write_file_record(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let records = match parse_file_writes(request.pdu.data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for record in records {
    match self.file_store.put(record) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(response_frame(request, copy_bytes(request.pdu.data)))
}

///|
fn parse_file_references(
  data : Array[Byte],
) -> Result[Array[FileRecordReference], ModbusError] {
  if data.length() < 8 ||
    data[0].to_int() != data.length() - 1 ||
    (data.length() - 1) % 7 != 0 {
    return Err(InvalidLength)
  }
  let out : Array[FileRecordReference] = []
  let count = (data.length() - 1) / 7
  for index in 0..<count {
    let offset = 1 + index * 7
    if data[offset] != 6 {
      return Err(InvalidData)
    }
    let file_number = (data[offset + 1].to_uint16() << 8) |
      data[offset + 2].to_uint16()
    let record_number = (data[offset + 3].to_uint16() << 8) |
      data[offset + 4].to_uint16()
    let record_length = (data[offset + 5].to_uint16() << 8) |
      data[offset + 6].to_uint16()
    match FileRecordReference::new(file_number, record_number, record_length) {
      Ok(reference) => out.push(reference)
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
fn parse_file_writes(
  data : Array[Byte],
) -> Result[Array[FileRecordWrite], ModbusError] {
  if data.length() < 9 || data[0].to_int() != data.length() - 1 {
    return Err(InvalidLength)
  }
  let out : Array[FileRecordWrite] = []
  let mut offset = 1
  while offset < data.length() {
    if offset + 7 > data.length() || data[offset] != 6 {
      return Err(InvalidData)
    }
    let file_number = (data[offset + 1].to_uint16() << 8) |
      data[offset + 2].to_uint16()
    let record_number = (data[offset + 3].to_uint16() << 8) |
      data[offset + 4].to_uint16()
    let record_length = (data[offset + 5].to_uint16() << 8) |
      data[offset + 6].to_uint16()
    let value_bytes = record_length.to_int() * 2
    if offset + 7 + value_bytes > data.length() {
      return Err(Incomplete)
    }
    let values : Array[UInt16] = []
    for index in 0..<record_length.to_int() {
      let at = offset + 7 + index * 2
      values.push((data[at].to_uint16() << 8) | data[at + 1].to_uint16())
    }
    let reference = match
      FileRecordReference::new(file_number, record_number, record_length) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match FileRecordWrite::new(reference, values) {
      Ok(value) => out.push(value)
      Err(error) => return Err(error)
    }
    offset += 7 + value_bytes
  }
  Ok(out)
}
