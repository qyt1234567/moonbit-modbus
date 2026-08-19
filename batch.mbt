///|
/// A named request in a batch operation.
pub(all) struct BatchItem {
  id : Int
  request : Frame
}

///|
pub fn BatchItem::new(
  id : Int,
  request : Frame,
) -> Result[BatchItem, ModbusError] {
  if id < 0 {
    Err(InvalidData)
  } else {
    Ok({ id, request })
  }
}

///|
/// An ordered batch plan used to pipeline independent requests.
pub struct BatchPlan {
  items : Array[BatchItem]
  max_items : Int
}

///|
pub fn BatchPlan::new(max_items? : Int = 128) -> Result[BatchPlan, ModbusError] {
  if max_items < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ items: [], max_items })
  }
}

///|
pub fn BatchPlan::add(
  self : BatchPlan,
  item : BatchItem,
) -> Result[Unit, ModbusError] {
  if self.items.length() >= self.max_items {
    return Err(CapacityExceeded)
  }
  for current in self.items {
    if current.id == item.id {
      return Err(InvalidData)
    }
  }
  match validate_frame(item.request, false) {
    Ok(_) => {
      self.items.push(item)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
pub fn BatchPlan::length(self : BatchPlan) -> Int {
  self.items.length()
}

///|
pub fn BatchPlan::item(
  self : BatchPlan,
  index : Int,
) -> Result[BatchItem, ModbusError] {
  if index < 0 || index >= self.items.length() {
    Err(InvalidAddress)
  } else {
    Ok(self.items[index])
  }
}

///|
pub fn BatchPlan::snapshot(self : BatchPlan) -> Array[BatchItem] {
  let out : Array[BatchItem] = []
  for item in self.items {
    out.push(item)
  }
  out
}

///|
/// The result of executing one batch item.
pub(all) enum BatchResult {
  Completed(Int, Frame)
  Failed(Int, ModbusError)
}

///|
/// Execute an ordered plan against a deterministic device.
pub fn BatchPlan::execute(
  self : BatchPlan,
  device : Device,
) -> Array[BatchResult] {
  let out : Array[BatchResult] = []
  for item in self.items {
    match device.handle(item.request) {
      Ok(response) => out.push(Completed(item.id, response))
      Err(error) => out.push(Failed(item.id, error))
    }
  }
  out
}

///|
pub fn batch_completed(results : Array[BatchResult]) -> Int {
  let mut count = 0
  for result in results {
    if result is Completed(_, _) {
      count += 1
    }
  }
  count
}

///|
pub fn batch_failed(results : Array[BatchResult]) -> Int {
  results.length() - batch_completed(results)
}

///|
/// Merge successful register responses from a batch into one ordered array.
pub fn batch_register_values(
  results : Array[BatchResult],
) -> Result[Array[UInt16], ModbusError] {
  let out : Array[UInt16] = []
  for result in results {
    match result {
      Completed(_, frame) =>
        match frame.pdu.data.length() {
          0 => ()
          _ => {
            let values = if frame.pdu.data[0].to_int() ==
              frame.pdu.data.length() - 1 {
              let bytes : Array[Byte] = []
              for index in 1..<frame.pdu.data.length() {
                bytes.push(frame.pdu.data[index])
              }
              bytes_to_registers(bytes, BigEndian)
            } else {
              registers(frame)
            }
            match values {
              Ok(items) =>
                for item in items {
                  out.push(item)
                }
              Err(error) => return Err(error)
            }
          }
        }
      Failed(_, error) => return Err(error)
    }
  }
  Ok(out)
}
