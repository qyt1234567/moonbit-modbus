///|
fn main {
  let frame = @moonbit-modbus.read_holding(1, 0, 4)
  let rtu = @moonbit-modbus.encode_rtu(frame)
  println("moonbit-modbus demo: RTU request bytes=\{rtu.length()}")
}
