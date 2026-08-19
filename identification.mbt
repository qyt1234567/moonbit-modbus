///|
/// Device-identification access category used by MEI type 0x0E.
pub(all) enum DeviceIdCategory {
  Basic
  Regular
  Extended
  Individual(Byte)
} derive(Debug, Eq)

///|
pub fn DeviceIdCategory::to_byte(category : DeviceIdCategory) -> Byte {
  match category {
    Basic => 1
    Regular => 2
    Extended => 3
    Individual(value) => value
  }
}

///|
pub fn device_id_category(value : Byte) -> DeviceIdCategory {
  match value {
    1 => Basic
    2 => Regular
    3 => Extended
    other => Individual(other)
  }
}

///|
/// One TLV object returned by a device-identification response.
pub(all) struct DeviceIdObject {
  object_id : Byte
  value : String
}

///|
pub fn DeviceIdObject::new(
  object_id : Byte,
  value : String,
) -> Result[DeviceIdObject, ModbusError] {
  if value.length() > 245 {
    Err(InvalidLength)
  } else {
    Ok({ object_id, value })
  }
}

///|
/// Parsed MEI device-identification response metadata.
pub(all) struct DeviceIdentification {
  category : DeviceIdCategory
  conformity : Byte
  more_follows : Bool
  next_object_id : Byte
  objects : Array[DeviceIdObject]
}

///|
/// Build a Read Device Identification request.
pub fn read_device_identification(
  unit_id : Byte,
  category : DeviceIdCategory,
  object_id : Byte,
) -> Result[Frame, ModbusError] {
  if !is_valid_unit_id(unit_id) {
    Err(InvalidUnitId)
  } else {
    Ok({
      unit_id,
      pdu: { function: 43, data: [0x0E, category.to_byte(), object_id] },
    })
  }
}

///|
/// Encode an identification response from typed objects.
pub fn encode_device_identification(
  unit_id : Byte,
  category : DeviceIdCategory,
  conformity : Byte,
  more_follows : Bool,
  next_object_id : Byte,
  objects : Array[DeviceIdObject],
) -> Result[Frame, ModbusError] {
  let data : Array[Byte] = [
    0x0E,
    0x01,
    category.to_byte(),
    conformity,
    if more_follows {
      0xFF
    } else {
      0
    },
    next_object_id,
    objects.length().to_byte(),
  ]
  for object in objects {
    if object.value.length() > 255 {
      return Err(InvalidLength)
    }
    data.push(object.object_id)
    data.push(object.value.length().to_byte())
    for code_unit in object.value {
      data.push(code_unit.to_int().to_byte())
    }
  }
  if data.length() > 253 {
    Err(InvalidLength)
  } else {
    Ok({ unit_id, pdu: { function: 43, data } })
  }
}

///|
/// Decode a Read Device Identification response into TLV objects.
pub fn decode_device_identification(
  request : Frame,
  response : Frame,
) -> Result[DeviceIdentification, ModbusError] {
  match expect_normal(request, response) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if response.pdu.data.length() < 7 || response.pdu.data[0] != 0x0E {
    return Err(InvalidData)
  }
  let category = device_id_category(response.pdu.data[2])
  let objects : Array[DeviceIdObject] = []
  let mut offset = 7
  while offset < response.pdu.data.length() {
    if offset + 2 > response.pdu.data.length() {
      return Err(Incomplete)
    }
    let id = response.pdu.data[offset]
    let length = response.pdu.data[offset + 1].to_int()
    if offset + 2 + length > response.pdu.data.length() {
      return Err(Incomplete)
    }
    let value = StringBuilder()
    for index in 0..<length {
      value.write_char(response.pdu.data[offset + 2 + index].to_char())
    }
    match DeviceIdObject::new(id, value.to_string()) {
      Ok(object) => objects.push(object)
      Err(error) => return Err(error)
    }
    offset += 2 + length
  }
  Ok({
    category,
    conformity: response.pdu.data[3],
    more_follows: response.pdu.data[4] != 0,
    next_object_id: response.pdu.data[5],
    objects,
  })
}

///|
/// A reusable identity catalogue for virtual devices.
pub struct DeviceIdentityCatalog {
  category : DeviceIdCategory
  objects : Array[DeviceIdObject]
  mut conformity : Byte
}

///|
pub fn DeviceIdentityCatalog::new(
  category? : DeviceIdCategory = Basic,
) -> DeviceIdentityCatalog {
  { category, objects: [], conformity: 1 }
}

///|
pub fn DeviceIdentityCatalog::add(
  self : DeviceIdentityCatalog,
  object : DeviceIdObject,
) -> Result[Unit, ModbusError] {
  if self.objects.length() >= 128 {
    Err(CapacityExceeded)
  } else {
    self.objects.push(object)
    Ok(())
  }
}

///|
pub fn DeviceIdentityCatalog::set_conformity(
  self : DeviceIdentityCatalog,
  conformity : Byte,
) -> Unit {
  self.conformity = conformity
}

///|
pub fn DeviceIdentityCatalog::response(
  self : DeviceIdentityCatalog,
  request : Frame,
) -> Result[Frame, ModbusError] {
  if request.pdu.function != 43 ||
    request.pdu.data.length() < 3 ||
    request.pdu.data[0] != 0x0E {
    return Err(InvalidFunction)
  }
  let requested_id = request.pdu.data[2]
  let selected : Array[DeviceIdObject] = []
  for object in self.objects {
    if object.object_id >= requested_id {
      selected.push(object)
    }
  }
  encode_device_identification(
    request.unit_id,
    self.category,
    self.conformity,
    false,
    0,
    selected,
  )
}

///|
pub fn DeviceIdentityCatalog::length(self : DeviceIdentityCatalog) -> Int {
  self.objects.length()
}

///|
pub fn DeviceIdentityCatalog::objects(
  self : DeviceIdentityCatalog,
) -> Array[DeviceIdObject] {
  let out : Array[DeviceIdObject] = []
  for object in self.objects {
    out.push(object)
  }
  out
}
