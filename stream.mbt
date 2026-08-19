///|
/// A bounded byte queue for adapters that receive arbitrary chunk sizes.
pub struct ByteQueue {
  data : Array[Byte]
  max_length : Int
}

///|
pub fn ByteQueue::new(
  max_length? : Int = 4096,
) -> Result[ByteQueue, ModbusError] {
  if max_length < 1 {
    Err(CapacityExceeded)
  } else {
    Ok({ data: [], max_length })
  }
}

///|
pub fn ByteQueue::length(self : ByteQueue) -> Int {
  self.data.length()
}

///|
pub fn ByteQueue::remaining(self : ByteQueue) -> Int {
  self.max_length - self.data.length()
}

///|
pub fn ByteQueue::is_empty(self : ByteQueue) -> Bool {
  self.data.length() == 0
}

///|
pub fn ByteQueue::push(
  self : ByteQueue,
  bytes : Array[Byte],
) -> Result[Unit, ModbusError] {
  if bytes.length() > self.remaining() {
    Err(CapacityExceeded)
  } else {
    for byte in bytes {
      self.data.push(byte)
    }
    Ok(())
  }
}

///|
pub fn ByteQueue::push_byte(
  self : ByteQueue,
  byte : Byte,
) -> Result[Unit, ModbusError] {
  self.push([byte])
}

///|
pub fn ByteQueue::peek(
  self : ByteQueue,
  index : Int,
) -> Result[Byte, ModbusError] {
  if index < 0 || index >= self.data.length() {
    Err(Incomplete)
  } else {
    Ok(self.data[index])
  }
}

///|
pub fn ByteQueue::take(
  self : ByteQueue,
  count : Int,
) -> Result[Array[Byte], ModbusError] {
  if count < 0 || count > self.data.length() {
    return Err(Incomplete)
  }
  let out : Array[Byte] = []
  for index in 0..<count {
    out.push(self.data[index])
  }
  discard_prefix(self.data, count)
  Ok(out)
}

///|
pub fn ByteQueue::take_all(self : ByteQueue) -> Array[Byte] {
  let out = copy_bytes(self.data)
  self.data.clear()
  out
}

///|
pub fn ByteQueue::find(self : ByteQueue, value : Byte) -> Int? {
  for index, current in self.data {
    if current == value {
      return Some(index)
    }
  }
  None
}

///|
pub fn ByteQueue::contains_sequence(
  self : ByteQueue,
  pattern : Array[Byte],
) -> Bool {
  if pattern.length() == 0 {
    return true
  }
  if pattern.length() > self.data.length() {
    return false
  }
  for start in 0..<(self.data.length() - pattern.length() + 1) {
    let mut matches = true
    for offset in 0..<pattern.length() {
      if self.data[start + offset] != pattern[offset] {
        matches = false
      }
    }
    if matches {
      return true
    }
  }
  false
}

///|
pub fn ByteQueue::clear(self : ByteQueue) -> Unit {
  self.data.clear()
}

///|
pub fn ByteQueue::snapshot(self : ByteQueue) -> Array[Byte] {
  copy_bytes(self.data)
}

///|
/// A frame stream combines a byte queue with the protocol parser.
pub struct FrameStream {
  mode : Mode
  parser : IncrementalParser
  queue : ByteQueue
  mut chunks : Int
  mut frames : Int
}

///|
pub fn FrameStream::new(
  mode : Mode,
  role? : ParserRole = Either,
  max_buffer? : Int = 4096,
  max_frame? : Int = 260,
) -> Result[FrameStream, ModbusError] {
  let queue = match ByteQueue::new(max_length=max_buffer) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    mode,
    parser: IncrementalParser::new(mode, max_frame~, role~),
    queue,
    chunks: 0,
    frames: 0,
  })
}

///|
pub fn FrameStream::push(
  self : FrameStream,
  bytes : Array[Byte],
) -> Result[Array[Frame], ModbusError] {
  match self.queue.push(bytes) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.chunks += 1
  let pending = self.queue.take_all()
  match self.parser.feed(pending) {
    Ok(frames) => {
      self.frames += frames.length()
      Ok(frames)
    }
    Err(error) => Err(error)
  }
}

///|
pub fn FrameStream::finish(self : FrameStream) -> Result[Frame, ModbusError] {
  self.parser.finish()
}

///|
pub fn FrameStream::reset(self : FrameStream) -> Unit {
  self.queue.clear()
  self.parser.reset()
}

///|
pub fn FrameStream::mode(self : FrameStream) -> Mode {
  self.mode
}

///|
pub fn FrameStream::chunks(self : FrameStream) -> Int {
  self.chunks
}

///|
pub fn FrameStream::frames(self : FrameStream) -> Int {
  self.frames
}

///|
/// Split a byte array into bounded chunks for transport fuzzing and tests.
pub fn chunk_bytes(
  bytes : Array[Byte],
  chunk_size : Int,
) -> Result[Array[Array[Byte]], ModbusError] {
  if chunk_size < 1 {
    return Err(InvalidQuantity)
  }
  let out : Array[Array[Byte]] = []
  let mut offset = 0
  while offset < bytes.length() {
    let end = if offset + chunk_size < bytes.length() {
      offset + chunk_size
    } else {
      bytes.length()
    }
    let chunk : Array[Byte] = []
    for index in offset..<end {
      chunk.push(bytes[index])
    }
    out.push(chunk)
    offset = end
  }
  Ok(out)
}

///|
/// Reassemble byte chunks and check their total size.
pub fn join_chunks(
  chunks : Array[Array[Byte]],
  max_length : Int,
) -> Result[Array[Byte], ModbusError] {
  if max_length < 0 {
    return Err(InvalidLength)
  }
  let out : Array[Byte] = []
  for chunk in chunks {
    if out.length() + chunk.length() > max_length {
      return Err(CapacityExceeded)
    }
    for byte in chunk {
      out.push(byte)
    }
  }
  Ok(out)
}
