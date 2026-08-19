///|
/// A Modbus file-record selector.
pub(all) struct FileRecordReference {
  reference_type : Byte
  file_number : UInt16
  record_number : UInt16
  record_length : UInt16
}

///|
pub fn FileRecordReference::new(
  file_number : UInt16,
  record_number : UInt16,
  record_length : UInt16,
  reference_type? : Byte = 6,
) -> Result[FileRecordReference, ModbusError] {
  if record_length < 1 || record_length > 125 {
    Err(InvalidQuantity)
  } else {
    Ok({ reference_type, file_number, record_number, record_length })
  }
}

///|
pub fn FileRecordReference::encoded_length(_self : FileRecordReference) -> Int {
  7
}

///|
fn encode_file_reference(
  out : Array[Byte],
  reference : FileRecordReference,
) -> Unit {
  out.push(reference.reference_type)
  out.push((reference.file_number >> 8).to_byte())
  out.push(reference.file_number.to_byte())
  out.push((reference.record_number >> 8).to_byte())
  out.push(reference.record_number.to_byte())
  out.push((reference.record_length >> 8).to_byte())
  out.push(reference.record_length.to_byte())
}

///|
/// Build a Read File Record request (function 20).
pub fn read_file_record(
  unit_id : Byte,
  references : Array[FileRecordReference],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if references.length() < 1 || references.length() > 35 {
    return Err(InvalidQuantity)
  }
  let data : Array[Byte] = [0]
  for reference in references {
    if reference.reference_type != 6 {
      return Err(InvalidData)
    }
    encode_file_reference(data, reference)
  }
  data[0] = (data.length() - 1).to_byte()
  Ok({ unit_id, pdu: { function: 20, data } })
}

///|
/// A file-record write item combines a selector and its register payload.
pub(all) struct FileRecordWrite {
  reference : FileRecordReference
  values : Array[UInt16]
}

///|
pub fn FileRecordWrite::new(
  reference : FileRecordReference,
  values : Array[UInt16],
) -> Result[FileRecordWrite, ModbusError] {
  if values.length() != reference.record_length.to_int() {
    Err(InvalidQuantity)
  } else {
    Ok({ reference, values })
  }
}

///|
/// Build a Write File Record request (function 21).
pub fn write_file_record(
  unit_id : Byte,
  records : Array[FileRecordWrite],
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  if records.length() < 1 || records.length() > 35 {
    return Err(InvalidQuantity)
  }
  let data : Array[Byte] = [0]
  for record in records {
    if record.reference.reference_type != 6 ||
      record.values.length() != record.reference.record_length.to_int() {
      return Err(InvalidData)
    }
    encode_file_reference(data, record.reference)
    for value in record.values {
      data.push((value >> 8).to_byte())
      data.push(value.to_byte())
    }
  }
  data[0] = (data.length() - 1).to_byte()
  if data.length() > 253 {
    Err(InvalidLength)
  } else {
    Ok({ unit_id, pdu: { function: 21, data } })
  }
}

///|
/// Decode the values returned for a Read File Record response.
pub fn decode_file_record_response(
  request : Frame,
  response : Frame,
) -> Result[Array[Array[UInt16]], ModbusError] {
  match expect_file_response(request, response, 20) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 1 ||
    response.pdu.data[0].to_int() != response.pdu.data.length() - 1 {
    return Err(InvalidByteCount)
  }
  let references = match parse_file_references(request.pdu.data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let output : Array[Array[UInt16]] = []
  let mut offset = 1
  for reference in references {
    let value_count = reference.record_length.to_int()
    let value_bytes = value_count * 2
    if offset >= response.pdu.data.length() ||
      response.pdu.data[offset] != reference.reference_type {
      return Err(InvalidData)
    }
    if offset + 1 + value_bytes > response.pdu.data.length() {
      return Err(Incomplete)
    }
    let values : Array[UInt16] = []
    for index in 0..<value_count {
      let at = offset + 1 + index * 2
      values.push(
        (response.pdu.data[at].to_uint16() << 8) |
        response.pdu.data[at + 1].to_uint16(),
      )
    }
    output.push(values)
    offset += 1 + value_bytes
  }
  if offset != response.pdu.data.length() {
    Err(InvalidLength)
  } else {
    Ok(output)
  }
}

///|
/// Decode the echo of a Write File Record response.
pub fn decode_file_record_write_response(
  request : Frame,
  response : Frame,
) -> Result[Unit, ModbusError] {
  match expect_file_response(request, response, 21) {
    Err(error) => Err(error)
    Ok(_) =>
      if response.pdu.data == request.pdu.data {
        Ok(())
      } else {
        Err(InvalidData)
      }
  }
}

///|
fn expect_file_response(
  request : Frame,
  response : Frame,
  function : Byte,
) -> Result[Unit, ModbusError] {
  if request.pdu.function != function ||
    response.pdu.function != function ||
    request.unit_id != response.unit_id {
    Err(InvalidFunction)
  } else if response.is_exception() {
    Err(InvalidData)
  } else {
    Ok(())
  }
}

///|
/// A bounded in-memory store for file records used by simulators.
pub(all) struct FileRecordStore {
  records : Array[FileRecordWrite]
  max_records : Int
}

///|
pub fn FileRecordStore::new(
  max_records? : Int = 64,
) -> Result[FileRecordStore, ModbusError] {
  if max_records < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ records: [], max_records })
  }
}

///|
pub fn FileRecordStore::put(
  self : FileRecordStore,
  record : FileRecordWrite,
) -> Result[Unit, ModbusError] {
  for index in 0..<self.records.length() {
    let current = self.records[index]
    if current.reference.file_number == record.reference.file_number &&
      current.reference.record_number == record.reference.record_number {
      self.records[index] = record
      return Ok(())
    }
  }
  if self.records.length() >= self.max_records {
    Err(CapacityExceeded)
  } else {
    self.records.push(record)
    Ok(())
  }
}

///|
pub fn FileRecordStore::get(
  self : FileRecordStore,
  reference : FileRecordReference,
) -> Result[Array[UInt16], ModbusError] {
  for record in self.records {
    if record.reference.file_number == reference.file_number &&
      record.reference.record_number == reference.record_number {
      if reference.record_length.to_int() > record.values.length() {
        return Err(InvalidQuantity)
      }
      let out : Array[UInt16] = []
      for index in 0..<reference.record_length.to_int() {
        out.push(record.values[index])
      }
      return Ok(out)
    }
  }
  Err(InvalidAddress)
}

///|
pub fn FileRecordStore::length(self : FileRecordStore) -> Int {
  self.records.length()
}

///|
pub fn FileRecordStore::clear(self : FileRecordStore) -> Unit {
  self.records.clear()
}
