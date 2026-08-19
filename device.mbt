///|
/// A response returned by a virtual or embedded device service.
pub(all) enum DeviceResponse {
  Reply(Frame)
  NoReply
}

///|
/// A protocol-level Modbus device backed by four bounded data tables.
pub struct Device {
  unit_id : Byte
  memory : DeviceMemory
  file_store : FileRecordStore
  mut server_id : Array[Byte]
  mut event_count : UInt16
  mut busy : Bool
  mut exception_count : Int
}

///|
/// Create a device with configurable table capacities.
pub fn Device::new(
  unit_id : Byte,
  coil_capacity? : Int = 2000,
  register_capacity? : Int = 125,
) -> Result[Device, ModbusError] {
  if !is_valid_unit_id(unit_id, broadcast=false) {
    return Err(InvalidUnitId)
  }
  match
    (
      DeviceMemory::new(coil_capacity~, register_capacity~),
      FileRecordStore::new(),
    ) {
    (Ok(memory), Ok(file_store)) =>
      Ok({
        unit_id,
        memory,
        file_store,
        server_id: [1, 0, 0],
        event_count: 0,
        busy: false,
        exception_count: 0,
      })
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }
}

///|
pub fn Device::unit_id(self : Device) -> Byte {
  self.unit_id
}

///|
pub fn Device::memory(self : Device) -> DeviceMemory {
  self.memory
}

///|
pub fn Device::file_store(self : Device) -> FileRecordStore {
  self.file_store
}

///|
pub fn Device::event_count(self : Device) -> UInt16 {
  self.event_count
}

///|
pub fn Device::exception_count(self : Device) -> Int {
  self.exception_count
}

///|
pub fn Device::set_busy(self : Device, busy : Bool) -> Unit {
  self.busy = busy
}

///|
pub fn Device::is_busy(self : Device) -> Bool {
  self.busy
}

///|
pub fn Device::set_server_id(
  self : Device,
  values : Array[Byte],
) -> Result[Unit, ModbusError] {
  if values.length() < 1 || values.length() > 245 {
    Err(InvalidLength)
  } else {
    self.server_id = copy_bytes(values)
    Ok(())
  }
}

///|
pub fn Device::server_id(self : Device) -> Array[Byte] {
  copy_bytes(self.server_id)
}

///|
/// Handle a request and return a normal or exception response.
pub fn Device::handle(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  if request.unit_id != self.unit_id && request.unit_id != 0 {
    return Err(UnitMismatch)
  }
  if request.unit_id == 0 && is_read_request(request.pdu.function) {
    return Err(NoResponse)
  }
  match validate_pdu(request.pdu) {
    Err(error) => {
      self.exception_count += 1
      Ok(error_response(request, error))
    }
    Ok(_) => {
      if self.busy && !is_write_request(request.pdu.function) {
        self.exception_count += 1
        return Ok(
          typed_exception_response(
            request.unit_id,
            request.pdu.function,
            ServerDeviceBusy,
          ),
        )
      }
      match self.handle_valid(request) {
        Ok(response) => {
          self.event_count += 1
          if request.unit_id == 0 {
            Err(NoResponse)
          } else {
            Ok(response)
          }
        }
        Err(error) => {
          self.exception_count += 1
          Ok(error_response(request, error))
        }
      }
    }
  }
}

///|
/// Handle a request while making broadcast no-response semantics explicit.
pub fn Device::serve(
  self : Device,
  request : Frame,
) -> Result[DeviceResponse, ModbusError] {
  match self.handle(request) {
    Ok(response) => Ok(Reply(response))
    Err(NoResponse) => Ok(NoReply)
    Err(error) => Err(error)
  }
}

///|
fn is_read_request(function : Byte) -> Bool {
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
fn is_write_request(function : Byte) -> Bool {
  function == 5 ||
  function == 6 ||
  function == 15 ||
  function == 16 ||
  function == 21 ||
  function == 22 ||
  function == 23
}

///|
fn Device::handle_valid(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  match function_code(request.pdu.function) {
    ReadCoils => self.handle_read_coils(request, false)
    ReadDiscreteInputs => self.handle_read_coils(request, true)
    ReadHoldingRegisters => self.handle_read_registers(request, false)
    ReadInputRegisters => self.handle_read_registers(request, true)
    WriteSingleCoil => self.handle_write_single_coil(request)
    WriteSingleRegister => self.handle_write_single_register(request)
    WriteMultipleCoils => self.handle_write_multiple_coils(request)
    WriteMultipleRegisters => self.handle_write_multiple_registers(request)
    MaskWriteRegister => self.handle_mask_write(request)
    ReadWriteMultipleRegisters => self.handle_read_write(request)
    ReadFileRecord => self.handle_read_file_record(request)
    WriteFileRecord => self.handle_write_file_record(request)
    ReadExceptionStatus => Ok(response_frame(request, [0]))
    Diagnostics => Ok(response_frame(request, copy_bytes(request.pdu.data)))
    GetCommEventCounter =>
      Ok({
        unit_id: request.unit_id,
        pdu: {
          function: 11,
          data: [
            (self.event_count >> 8).to_byte(),
            self.event_count.to_byte(),
            (self.event_count >> 8).to_byte(),
            self.event_count.to_byte(),
          ],
        },
      })
    GetCommEventLog => Ok(response_frame(request, [0, 0, 0, 0, 0, 0, 0]))
    ReportServerId => Ok(response_frame(request, self.server_payload()))
    ReadFifoQueue => Ok(response_frame(request, [0, 2, 0, 0]))
    _ => Err(Unsupported)
  }
}

///|
fn Device::handle_read_coils(
  self : Device,
  request : Frame,
  discrete : Bool,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let quantity = ((request.pdu.data[2].to_uint16() << 8) |
  request.pdu.data[3].to_uint16()).to_int()
  let values = if discrete {
    self.memory.discrete_inputs().read(address, quantity)
  } else {
    self.memory.coils().read(address, quantity)
  }
  match values {
    Err(error) => Err(error)
    Ok(bits) => {
      let packed = pack_bits(bits)
      let data : Array[Byte] = [packed.length().to_byte()]
      for byte in packed {
        data.push(byte)
      }
      Ok(response_frame(request, data))
    }
  }
}

///|
fn Device::handle_read_registers(
  self : Device,
  request : Frame,
  input : Bool,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let quantity = ((request.pdu.data[2].to_uint16() << 8) |
  request.pdu.data[3].to_uint16()).to_int()
  let values = if input {
    self.memory.input_registers().read(address, quantity)
  } else {
    self.memory.holding_registers().read(address, quantity)
  }
  match values {
    Err(error) => Err(error)
    Ok(registers) => {
      let bytes = registers_to_bytes(registers, BigEndian)
      let data : Array[Byte] = [bytes.length().to_byte()]
      for byte in bytes {
        data.push(byte)
      }
      Ok(response_frame(request, data))
    }
  }
}

///|
fn Device::handle_write_single_coil(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let value = request.pdu.data[2] == 0xFF && request.pdu.data[3] == 0
  match self.memory.coils().set(address, value) {
    Ok(_) => Ok(response_frame(request, copy_bytes(request.pdu.data)))
    Err(error) => Err(error)
  }
}

///|
fn Device::handle_write_single_register(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let value = (request.pdu.data[2].to_uint16() << 8) |
    request.pdu.data[3].to_uint16()
  match self.memory.holding_registers().set(address, value) {
    Ok(_) => Ok(response_frame(request, copy_bytes(request.pdu.data)))
    Err(error) => Err(error)
  }
}

///|
fn Device::handle_write_multiple_coils(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let quantity = ((request.pdu.data[2].to_uint16() << 8) |
  request.pdu.data[3].to_uint16()).to_int()
  let bytes : Array[Byte] = []
  for index in 5..<request.pdu.data.length() {
    bytes.push(request.pdu.data[index])
  }
  let values = match unpack_bits(bytes, quantity) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.memory.coils().write(address, values) {
    Ok(_) =>
      Ok({
        unit_id: request.unit_id,
        pdu: {
          function: 15,
          data: [
            request.pdu.data[0],
            request.pdu.data[1],
            request.pdu.data[2],
            request.pdu.data[3],
          ],
        },
      })
    Err(error) => Err(error)
  }
}

///|
fn Device::handle_write_multiple_registers(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let bytes : Array[Byte] = []
  for index in 5..<request.pdu.data.length() {
    bytes.push(request.pdu.data[index])
  }
  let values = match bytes_to_registers(bytes, BigEndian) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.memory.holding_registers().write(address, values) {
    Ok(_) =>
      Ok({
        unit_id: request.unit_id,
        pdu: {
          function: 16,
          data: [
            request.pdu.data[0],
            request.pdu.data[1],
            request.pdu.data[2],
            request.pdu.data[3],
          ],
        },
      })
    Err(error) => Err(error)
  }
}

///|
fn Device::handle_mask_write(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let and_mask = (request.pdu.data[2].to_uint16() << 8) |
    request.pdu.data[3].to_uint16()
  let or_mask = (request.pdu.data[4].to_uint16() << 8) |
    request.pdu.data[5].to_uint16()
  match self.memory.holding_registers().write_mask(address, and_mask, or_mask) {
    Ok(_) => Ok(response_frame(request, copy_bytes(request.pdu.data)))
    Err(error) => Err(error)
  }
}

///|
fn Device::handle_read_write(
  self : Device,
  request : Frame,
) -> Result[Frame, ModbusError] {
  let read_address = (request.pdu.data[0].to_uint16() << 8) |
    request.pdu.data[1].to_uint16()
  let read_quantity = ((request.pdu.data[2].to_uint16() << 8) |
  request.pdu.data[3].to_uint16()).to_int()
  let write_address = (request.pdu.data[4].to_uint16() << 8) |
    request.pdu.data[5].to_uint16()
  let bytes : Array[Byte] = []
  for index in 9..<request.pdu.data.length() {
    bytes.push(request.pdu.data[index])
  }
  let values = match bytes_to_registers(bytes, BigEndian) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.memory.holding_registers().write(write_address, values) {
    Err(error) => Err(error)
    Ok(_) =>
      match self.memory.holding_registers().read(read_address, read_quantity) {
        Err(error) => Err(error)
        Ok(result) => {
          let payload = registers_to_bytes(result, BigEndian)
          let data : Array[Byte] = [payload.length().to_byte()]
          for byte in payload {
            data.push(byte)
          }
          Ok(response_frame(request, data))
        }
      }
  }
}

///|
fn Device::server_payload(self : Device) -> Array[Byte] {
  let data : Array[Byte] = []
  for byte in self.server_id {
    data.push(byte)
  }
  data.push(0xFF)
  data
}

///|
/// A compact device health snapshot for dashboards and polling logs.
pub(all) struct DeviceHealth {
  unit_id : Byte
  event_count : UInt16
  exception_count : Int
  busy : Bool
}

///|
pub fn Device::health(self : Device) -> DeviceHealth {
  {
    unit_id: self.unit_id,
    event_count: self.event_count,
    exception_count: self.exception_count,
    busy: self.busy,
  }
}
