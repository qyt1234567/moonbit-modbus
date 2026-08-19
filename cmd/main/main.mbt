///|
fn main {
  let request = @moonbit-modbus.read_holding(1, 0, 4)
  let rtu = @moonbit-modbus.encode_rtu(request)
  println("moonbit-modbus demo")
  println("request=" + @moonbit-modbus.format_frame(request))
  println("rtu-bytes=" + rtu.length().to_string())
  match @moonbit-modbus.Device::new(1) {
    Err(_) => println("device=unavailable")
    Ok(device) =>
      match device.handle(request) {
        Err(_) => println("device=error")
        Ok(response) =>
          println("response=" + @moonbit-modbus.format_frame(response))
      }
  }
}
