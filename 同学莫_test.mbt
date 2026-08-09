///|
test "crc16 known vector" {
  let crc = crc16([1, 3, 0, 0, 0, 10])
  inspect(crc.to_string(radix=16), content="cdc5")
}

///|
test "rtu round trip" {
  let bytes = encode_rtu(read_holding(1, 0, 10))
  inspect(decode_rtu(bytes) is Ok(_), content="true")
}

///|
test "tcp round trip" {
  let bytes = encode_tcp(42, write_single_register(7, 12, 345))
  match decode_tcp(bytes) {
    Ok((transaction, frame)) => {
      inspect(transaction, content="42")
      inspect(frame.unit_id.to_int(), content="7")
      inspect(frame.pdu.function.to_int(), content="6")
    }
    Err(_) => fail("TCP frame should decode")
  }
}

///|
test "ascii round trip" {
  inspect(
    decode_ascii(encode_ascii(read_holding(1, 16, 2))) is Ok(_),
    content="true",
  )
}

///|
test "register mapping" {
  let frame : Frame = {
    unit_id: 1,
    pdu: { function: 3, data: [0xFF, 0xFE, 0, 1] },
  }
  match registers(frame) {
    Ok(values) => {
      inspect(signed_register(values[0]), content="-2")
      inspect(values[1].to_int(), content="1")
    }
    Err(_) => fail("registers should decode")
  }
}

///|
test "extended function builders" {
  match read_coils(1, 0, 8) {
    Ok(frame) => {
      inspect(frame.pdu.function.to_int(), content="1")
      inspect(frame.pdu.data.length(), content="4")
    }
    Err(_) => fail("valid coil request should build")
  }
  match write_multiple_registers(1, 4, [10, 20]) {
    Ok(frame) => {
      inspect(frame.pdu.function.to_int(), content="16")
      inspect(frame.pdu.data[4].to_int(), content="4")
    }
    Err(_) => fail("valid write request should build")
  }
  let error = exception_response(1, 3, 2)
  inspect(is_exception(error), content="true")
  inspect(base_function(error).to_int(), content="3")
}
