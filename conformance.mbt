///|
/// A portable conformance vector for transport and frame decoders.
pub(all) struct ConformanceVector {
  name : String
  mode : Mode
  bytes : Array[Byte]
  expected_function : Byte?
  expected_error : ModbusError?
}

///|
pub fn ConformanceVector::valid(
  name : String,
  mode : Mode,
  bytes : Array[Byte],
  expected_function : Byte,
) -> ConformanceVector {
  {
    name,
    mode,
    bytes,
    expected_function: Some(expected_function),
    expected_error: None,
  }
}

///|
pub fn ConformanceVector::invalid(
  name : String,
  mode : Mode,
  bytes : Array[Byte],
  expected_error : ModbusError,
) -> ConformanceVector {
  {
    name,
    mode,
    bytes,
    expected_function: None,
    expected_error: Some(expected_error),
  }
}

///|
/// A vector execution result.
pub(all) struct ConformanceResult {
  name : String
  passed : Bool
  detail : String
}

///|
/// A reusable conformance suite.
pub struct ConformanceSuite {
  vectors : Array[ConformanceVector]
}

///|
pub fn ConformanceSuite::new() -> ConformanceSuite {
  { vectors: [] }
}

///|
pub fn ConformanceSuite::add(
  self : ConformanceSuite,
  vector : ConformanceVector,
) -> Unit {
  self.vectors.push(vector)
}

///|
pub fn ConformanceSuite::length(self : ConformanceSuite) -> Int {
  self.vectors.length()
}

///|
pub fn ConformanceSuite::run(
  self : ConformanceSuite,
) -> Array[ConformanceResult] {
  let out : Array[ConformanceResult] = []
  for vector in self.vectors {
    match decode_transaction(vector.mode, vector.bytes) {
      Ok((_, frame)) =>
        match vector.expected_function {
          Some(function) =>
            if frame.pdu.function == function {
              out.push({ name: vector.name, passed: true, detail: "valid" })
            } else {
              out.push({
                name: vector.name,
                passed: false,
                detail: "function mismatch",
              })
            }
          None =>
            out.push({
              name: vector.name,
              passed: false,
              detail: "expected error",
            })
        }
      Err(error) =>
        match vector.expected_error {
          Some(expected) =>
            out.push({
              name: vector.name,
              passed: error == expected,
              detail: error_name(error),
            })
          None =>
            out.push({
              name: vector.name,
              passed: false,
              detail: error_name(error),
            })
        }
    }
  }
  out
}

///|
pub fn conformance_passed(results : Array[ConformanceResult]) -> Int {
  let mut count = 0
  for result in results {
    if result.passed {
      count += 1
    }
  }
  count
}

///|
pub fn conformance_failed(results : Array[ConformanceResult]) -> Int {
  results.length() - conformance_passed(results)
}

///|
/// Build protocol vectors from a known request in all three transports.
pub fn round_trip_vectors(frame : Frame) -> Array[ConformanceVector] {
  let out : Array[ConformanceVector] = []
  for mode in [Rtu, Ascii, Tcp] {
    let bytes = encode_mode(mode, frame)
    out.push(
      ConformanceVector::valid(mode_name(mode), mode, bytes, frame.pdu.function),
    )
  }
  out
}

///|
/// Run the same frame through every transport codec.
pub fn round_trip_all_modes(frame : Frame) -> Result[Array[Frame], ModbusError] {
  let out : Array[Frame] = []
  for mode in [Rtu, Ascii, Tcp] {
    match decode_mode(mode, encode_mode(mode, frame)) {
      Ok(value) => out.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(out)
}

///|
/// Generate boundary vectors for empty, short, and corrupt inputs.
pub fn boundary_vectors(frame : Frame) -> Array[ConformanceVector] {
  let out : Array[ConformanceVector] = []
  let rtu = encode_rtu(frame)
  out.push(ConformanceVector::invalid("rtu-empty", Rtu, [], Incomplete))
  out.push(ConformanceVector::invalid("rtu-short", Rtu, [rtu[0]], Incomplete))
  let corrupt = copy_bytes(rtu)
  if corrupt.length() > 2 {
    corrupt[corrupt.length() - 1] = corrupt[corrupt.length() - 1] ^ 1
  }
  out.push(ConformanceVector::invalid("rtu-crc", Rtu, corrupt, InvalidChecksum))
  let tcp = encode_tcp(1, frame)
  out.push(ConformanceVector::invalid("tcp-short", Tcp, [0, 0], Incomplete))
  let tcp_corrupt = copy_bytes(tcp)
  tcp_corrupt[2] = 1
  out.push(
    ConformanceVector::invalid("tcp-protocol", Tcp, tcp_corrupt, InvalidMbap),
  )
  let ascii = encode_ascii(frame)
  out.push(ConformanceVector::invalid("ascii-prefix", Ascii, [0], Incomplete))
  let ascii_corrupt = copy_bytes(ascii)
  ascii_corrupt[0] = 59
  out.push(
    ConformanceVector::invalid(
      "ascii-prefix-value",
      Ascii,
      ascii_corrupt,
      InvalidAscii,
    ),
  )
  out
}
