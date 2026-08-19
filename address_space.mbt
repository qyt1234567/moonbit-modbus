///|
/// A half-open address range in the Modbus 16-bit address space.
pub(all) struct AddressRange {
  start : UInt16
  length : Int
}

///|
pub fn AddressRange::new(
  start : UInt16,
  length : Int,
) -> Result[AddressRange, ModbusError] {
  if length < 1 || !valid_address_range(start, length) {
    Err(InvalidAddress)
  } else {
    Ok({ start, length })
  }
}

///|
pub fn AddressRange::start(self : AddressRange) -> UInt16 {
  self.start
}

///|
pub fn AddressRange::length(self : AddressRange) -> Int {
  self.length
}

///|
pub fn AddressRange::end_exclusive(self : AddressRange) -> Int {
  self.start.to_int() + self.length
}

///|
pub fn AddressRange::contains(self : AddressRange, address : UInt16) -> Bool {
  address.to_int() >= self.start.to_int() &&
  address.to_int() < self.end_exclusive()
}

///|
pub fn AddressRange::contains_range(
  self : AddressRange,
  other : AddressRange,
) -> Bool {
  other.start.to_int() >= self.start.to_int() &&
  other.end_exclusive() <= self.end_exclusive()
}

///|
pub fn AddressRange::overlaps(
  self : AddressRange,
  other : AddressRange,
) -> Bool {
  self.start.to_int() < other.end_exclusive() &&
  other.start.to_int() < self.end_exclusive()
}

///|
pub fn AddressRange::offset(
  self : AddressRange,
  address : UInt16,
) -> Result[Int, ModbusError] {
  if self.contains(address) {
    Ok(address.to_int() - self.start.to_int())
  } else {
    Err(InvalidAddress)
  }
}

///|
pub fn AddressRange::slice(
  self : AddressRange,
  offset : Int,
  length : Int,
) -> Result[AddressRange, ModbusError] {
  if offset < 0 || length < 1 || offset + length > self.length {
    Err(InvalidAddress)
  } else {
    AddressRange::new((self.start.to_int() + offset).to_uint16(), length)
  }
}

///|
/// Split a range into non-overlapping segments of at most `segment_length`.
pub fn AddressRange::split(
  self : AddressRange,
  segment_length : Int,
) -> Result[Array[AddressRange], ModbusError] {
  if segment_length < 1 {
    return Err(InvalidQuantity)
  }
  let out : Array[AddressRange] = []
  let mut offset = 0
  while offset < self.length {
    let size = if offset + segment_length < self.length {
      segment_length
    } else {
      self.length - offset
    }
    match self.slice(offset, size) {
      Ok(value) => out.push(value)
      Err(error) => return Err(error)
    }
    offset += size
  }
  Ok(out)
}

///|
/// A first-fit allocator for contiguous register or coil ranges.
pub struct AddressAllocator {
  capacity : Int
  used : Array[AddressRange]
}

///|
pub fn AddressAllocator::new(
  capacity : Int,
) -> Result[AddressAllocator, ModbusError] {
  if capacity < 1 || capacity > 65536 {
    Err(CapacityExceeded)
  } else {
    Ok({ capacity, used: [] })
  }
}

///|
pub fn AddressAllocator::allocate(
  self : AddressAllocator,
  length : Int,
) -> Result[AddressRange, ModbusError] {
  if length < 1 || length > self.capacity {
    return Err(CapacityExceeded)
  }
  let mut candidate = 0
  while candidate + length <= self.capacity {
    let range = AddressRange::new(candidate.to_uint16(), length).unwrap()
    let mut conflict = false
    for current in self.used {
      if current.overlaps(range) {
        conflict = true
      }
    }
    if !conflict {
      self.used.push(range)
      return Ok(range)
    }
    candidate += 1
  }
  Err(CapacityExceeded)
}

///|
pub fn AddressAllocator::release(
  self : AddressAllocator,
  range : AddressRange,
) -> Result[Unit, ModbusError] {
  for index in 0..<self.used.length() {
    if self.used[index].start == range.start &&
      self.used[index].length == range.length {
      let remaining : Array[AddressRange] = []
      for current in 0..<self.used.length() {
        if current != index {
          remaining.push(self.used[current])
        }
      }
      self.used.clear()
      for item in remaining {
        self.used.push(item)
      }
      return Ok(())
    }
  }
  Err(InvalidAddress)
}

///|
pub fn AddressAllocator::used_count(self : AddressAllocator) -> Int {
  self.used.length()
}

///|
pub fn AddressAllocator::used_capacity(self : AddressAllocator) -> Int {
  let mut total = 0
  for range in self.used {
    total += range.length
  }
  total
}

///|
pub fn AddressAllocator::free_capacity(self : AddressAllocator) -> Int {
  self.capacity - self.used_capacity()
}

///|
pub fn AddressAllocator::snapshot(
  self : AddressAllocator,
) -> Array[AddressRange] {
  let out : Array[AddressRange] = []
  for range in self.used {
    out.push(range)
  }
  out
}
