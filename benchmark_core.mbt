///|
/// Deterministic benchmark counters emitted by the command-line benchmark.
pub(all) struct BenchmarkResult {
  name : String
  iterations : Int
  successful : Int
  failed : Int
  bytes : Int
}

///|
pub fn BenchmarkResult::success_rate(self : BenchmarkResult) -> Float {
  if self.iterations == 0 {
    0.0
  } else {
    Float::from_int(self.successful) / Float::from_int(self.iterations)
  }
}

///|
pub fn BenchmarkResult::operations(self : BenchmarkResult) -> Int {
  self.successful + self.failed
}

///|
pub fn BenchmarkResult::summary(self : BenchmarkResult) -> String {
  self.name +
  " iterations=" +
  self.iterations.to_string() +
  " successful=" +
  self.successful.to_string() +
  " failed=" +
  self.failed.to_string() +
  " bytes=" +
  self.bytes.to_string()
}

///|
/// Run repeated CRC work over a representative RTU payload.
pub fn benchmark_crc(iterations : Int) -> Result[BenchmarkResult, ModbusError] {
  if iterations < 1 {
    return Err(InvalidQuantity)
  }
  let payload : Array[Byte] = [1, 3, 0, 0, 0, 32]
  let mut successful = 0
  let mut failed = 0
  let mut bytes = 0
  for _ in 0..<iterations {
    let crc = crc16(payload)
    if crc == 0x1244 {
      successful += 1
    } else {
      failed += 1
    }
    bytes += payload.length()
  }
  Ok({ name: "crc16", iterations, successful, failed, bytes })
}

///|
/// Run encode/decode round trips for the RTU transport.
pub fn benchmark_rtu_round_trip(
  iterations : Int,
) -> Result[BenchmarkResult, ModbusError] {
  if iterations < 1 {
    return Err(InvalidQuantity)
  }
  let frame = read_holding(1, 0, 32)
  let mut successful = 0
  let mut failed = 0
  let mut bytes = 0
  for _ in 0..<iterations {
    let wire = encode_rtu(frame)
    bytes += wire.length()
    match decode_rtu(wire) {
      Ok(decoded) =>
        if frames_equal(frame, decoded) {
          successful += 1
        } else {
          failed += 1
        }
      Err(_) => failed += 1
    }
  }
  Ok({ name: "rtu-round-trip", iterations, successful, failed, bytes })
}

///|
/// Run encode/decode round trips for the TCP transport.
pub fn benchmark_tcp_round_trip(
  iterations : Int,
) -> Result[BenchmarkResult, ModbusError] {
  if iterations < 1 {
    return Err(InvalidQuantity)
  }
  let frame = read_holding(1, 0, 32)
  let mut successful = 0
  let mut failed = 0
  let mut bytes = 0
  for index in 0..<iterations {
    let wire = encode_tcp(index.to_uint16(), frame)
    bytes += wire.length()
    match decode_tcp(wire) {
      Ok((transaction_id, decoded)) =>
        if transaction_id == index.to_uint16() && frames_equal(frame, decoded) {
          successful += 1
        } else {
          failed += 1
        }
      Err(_) => failed += 1
    }
  }
  Ok({ name: "tcp-round-trip", iterations, successful, failed, bytes })
}

///|
/// Run a device read workload over the in-memory server path.
pub fn benchmark_device_reads(
  iterations : Int,
) -> Result[BenchmarkResult, ModbusError] {
  if iterations < 1 {
    return Err(InvalidQuantity)
  }
  let device = match Device::new(1) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut successful = 0
  let mut failed = 0
  let mut bytes = 0
  for index in 0..<iterations {
    let request = read_holding(1, (index % 64).to_uint16(), 1)
    match device.handle(request) {
      Ok(response) => {
        successful += 1
        bytes += response.pdu.data.length()
      }
      Err(_) => failed += 1
    }
  }
  Ok({ name: "device-read", iterations, successful, failed, bytes })
}

///|
/// Run the standard local benchmark suite.
pub fn benchmark_suite(
  iterations : Int,
) -> Result[Array[BenchmarkResult], ModbusError] {
  let out : Array[BenchmarkResult] = []
  match benchmark_crc(iterations) {
    Ok(value) => out.push(value)
    Err(error) => return Err(error)
  }
  match benchmark_rtu_round_trip(iterations) {
    Ok(value) => out.push(value)
    Err(error) => return Err(error)
  }
  match benchmark_tcp_round_trip(iterations) {
    Ok(value) => out.push(value)
    Err(error) => return Err(error)
  }
  match benchmark_device_reads(iterations) {
    Ok(value) => out.push(value)
    Err(error) => return Err(error)
  }
  Ok(out)
}
