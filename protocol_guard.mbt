///|
/// Decision made before a frame enters a server or gateway pipeline.
pub(all) enum GuardDecision {
  AdmitFrame
  RejectFrame
  DeferFrame
  DuplicateFrame
  QuotaFrame
  OversizeFrame
} derive(Debug, Eq)

///|
/// Reason included in a protocol admission record.
pub(all) enum GuardReason {
  GuardAccepted
  GuardBadUnit
  GuardBadFunction
  GuardBadLength
  GuardDuplicate
  GuardRateLimited
  GuardTooLarge
  GuardUnknownPeer
} derive(Debug, Eq)

///|
/// Per-peer frame quota and size policy.
pub(all) struct ProtocolGuardPolicy {
  max_frame_bytes : Int
  max_frames : Int
  window : Int
  duplicate_window : Int
  allow_broadcast : Bool
  functions : Array[Byte]
}

///|
pub fn ProtocolGuardPolicy::new(
  max_frame_bytes? : Int = 260,
  max_frames? : Int = 100,
  window? : Int = 1000,
  duplicate_window? : Int = 200,
  allow_broadcast? : Bool = false,
) -> Result[ProtocolGuardPolicy, ModbusError] {
  if max_frame_bytes < 8 || max_frames < 1 || window < 1 || duplicate_window < 0 {
    return Err(InvalidData)
  }
  Ok({
    max_frame_bytes,
    max_frames,
    window,
    duplicate_window,
    allow_broadcast,
    functions: [1, 2, 3, 4, 5, 6, 15, 16, 22, 23],
  })
}

///|
pub fn ProtocolGuardPolicy::max_frame_bytes(self : ProtocolGuardPolicy) -> Int {
  self.max_frame_bytes
}

///|
pub fn ProtocolGuardPolicy::max_frames(self : ProtocolGuardPolicy) -> Int {
  self.max_frames
}

///|
pub fn ProtocolGuardPolicy::window(self : ProtocolGuardPolicy) -> Int {
  self.window
}

///|
pub fn ProtocolGuardPolicy::duplicate_window(self : ProtocolGuardPolicy) -> Int {
  self.duplicate_window
}

///|
pub fn ProtocolGuardPolicy::allow_broadcast(self : ProtocolGuardPolicy) -> Bool {
  self.allow_broadcast
}

///|
pub fn ProtocolGuardPolicy::function_allowed(
  self : ProtocolGuardPolicy,
  function : Byte,
) -> Bool {
  for allowed in self.functions {
    if allowed == function {
      return true
    }
  }
  false
}

///|
pub fn ProtocolGuardPolicy::add_function(
  self : ProtocolGuardPolicy,
  function : Byte,
) -> Result[Unit, ModbusError] {
  if function == 0 {
    return Err(InvalidFunction)
  }
  if !self.function_allowed(function) {
    self.functions.push(function)
  }
  Ok(())
}

///|
/// Immutable frame fingerprint for duplicate detection.
pub(all) struct FrameFingerprint {
  unit_id : Byte
  function : Byte
  data_length : Int
  checksum : Int
}

///|
pub fn FrameFingerprint::from_frame(frame : Frame) -> FrameFingerprint {
  let mut checksum = frame.unit_id.to_int() * 257 + frame.pdu.function.to_int()
  for byte in frame.pdu.data {
    checksum = checksum * 33 + byte.to_int()
  }
  {
    unit_id: frame.unit_id,
    function: frame.pdu.function,
    data_length: frame.pdu.data.length(),
    checksum,
  }
}

///|
pub fn FrameFingerprint::unit_id(self : FrameFingerprint) -> Byte {
  self.unit_id
}

///|
pub fn FrameFingerprint::function(self : FrameFingerprint) -> Byte {
  self.function
}

///|
pub fn FrameFingerprint::data_length(self : FrameFingerprint) -> Int {
  self.data_length
}

///|
pub fn FrameFingerprint::checksum(self : FrameFingerprint) -> Int {
  self.checksum
}

///|
pub fn FrameFingerprint::same(
  self : FrameFingerprint,
  other : FrameFingerprint,
) -> Bool {
  self.unit_id == other.unit_id &&
  self.function == other.function &&
  self.data_length == other.data_length &&
  self.checksum == other.checksum
}

///|
/// Admission event retained for metrics and support diagnostics.
pub(all) struct GuardEvent {
  sequence : Int
  timestamp : Int
  peer : String
  decision : GuardDecision
  reason : GuardReason
  unit_id : Byte
  function : Byte
  frame_bytes : Int
  fingerprint : FrameFingerprint
}

///|
pub fn GuardEvent::new(
  sequence : Int,
  timestamp : Int,
  peer : String,
  decision : GuardDecision,
  reason : GuardReason,
  frame : Frame,
) -> Result[GuardEvent, ModbusError] {
  if sequence < 1 || timestamp < 0 || peer == "" {
    return Err(InvalidData)
  }
  Ok({
    sequence,
    timestamp,
    peer,
    decision,
    reason,
    unit_id: frame.unit_id,
    function: frame.pdu.function,
    frame_bytes: frame.pdu.data.length() + 2,
    fingerprint: FrameFingerprint::from_frame(frame),
  })
}

///|
pub fn GuardEvent::sequence(self : GuardEvent) -> Int {
  self.sequence
}

///|
pub fn GuardEvent::timestamp(self : GuardEvent) -> Int {
  self.timestamp
}

///|
pub fn GuardEvent::peer(self : GuardEvent) -> String {
  self.peer
}

///|
pub fn GuardEvent::decision(self : GuardEvent) -> GuardDecision {
  self.decision
}

///|
pub fn GuardEvent::reason(self : GuardEvent) -> GuardReason {
  self.reason
}

///|
pub fn GuardEvent::unit_id(self : GuardEvent) -> Byte {
  self.unit_id
}

///|
pub fn GuardEvent::function(self : GuardEvent) -> Byte {
  self.function
}

///|
pub fn GuardEvent::frame_bytes(self : GuardEvent) -> Int {
  self.frame_bytes
}

///|
pub fn GuardEvent::fingerprint(self : GuardEvent) -> FrameFingerprint {
  self.fingerprint
}

///|
pub fn guard_decision_name(value : GuardDecision) -> String {
  match value {
    AdmitFrame => "admit"
    RejectFrame => "reject"
    DeferFrame => "defer"
    DuplicateFrame => "duplicate"
    QuotaFrame => "quota"
    OversizeFrame => "oversize"
  }
}

///|
pub fn guard_reason_name(value : GuardReason) -> String {
  match value {
    GuardAccepted => "accepted"
    GuardBadUnit => "bad-unit"
    GuardBadFunction => "bad-function"
    GuardBadLength => "bad-length"
    GuardDuplicate => "duplicate"
    GuardRateLimited => "rate-limited"
    GuardTooLarge => "too-large"
    GuardUnknownPeer => "unknown-peer"
  }
}

///|
/// Per-peer admission state.
pub(all) struct PeerGuardState {
  peer : String
  timestamps : Array[Int]
  fingerprints : Array[(FrameFingerprint, Int)]
  mut accepted : Int
  mut rejected : Int
}

///|
pub fn PeerGuardState::new(
  peer : String,
) -> Result[PeerGuardState, ModbusError] {
  if peer == "" {
    Err(InvalidData)
  } else {
    Ok({ peer, timestamps: [], fingerprints: [], accepted: 0, rejected: 0 })
  }
}

///|
pub fn PeerGuardState::peer(self : PeerGuardState) -> String {
  self.peer
}

///|
pub fn PeerGuardState::accepted(self : PeerGuardState) -> Int {
  self.accepted
}

///|
pub fn PeerGuardState::rejected(self : PeerGuardState) -> Int {
  self.rejected
}

///|
pub fn PeerGuardState::prune(
  self : PeerGuardState,
  now : Int,
  policy : ProtocolGuardPolicy,
) -> Result[Unit, ModbusError] {
  if now < 0 {
    return Err(InvalidData)
  }
  while self.timestamps.length() > 0 &&
        now - self.timestamps[0] > policy.window() {
    ignore(self.timestamps.remove(0))
  }
  while self.fingerprints.length() > 0 &&
        now - self.fingerprints[0].1 > policy.duplicate_window() {
    ignore(self.fingerprints.remove(0))
  }
  Ok(())
}

///|
pub fn PeerGuardState::frame_count(self : PeerGuardState) -> Int {
  self.timestamps.length()
}

///|
pub fn PeerGuardState::duplicate(
  self : PeerGuardState,
  fingerprint : FrameFingerprint,
  now : Int,
  policy : ProtocolGuardPolicy,
) -> Bool {
  for item in self.fingerprints {
    if item.0.same(fingerprint) && now - item.1 <= policy.duplicate_window() {
      return true
    }
  }
  false
}

///|
pub fn PeerGuardState::record(
  self : PeerGuardState,
  fingerprint : FrameFingerprint,
  now : Int,
  accepted : Bool,
) -> Unit {
  self.timestamps.push(now)
  self.fingerprints.push((fingerprint, now))
  if accepted {
    self.accepted += 1
  } else {
    self.rejected += 1
  }
}

///|
/// A protocol admission guard safe to use before decoding application data.
pub(all) struct ProtocolGuard {
  policy : ProtocolGuardPolicy
  peers : Array[PeerGuardState]
  events : Array[GuardEvent]
  max_peers : Int
  max_events : Int
  mut sequence : Int
}

///|
pub fn ProtocolGuard::new(
  policy : ProtocolGuardPolicy,
  max_peers? : Int = 1024,
  max_events? : Int = 8192,
) -> Result[ProtocolGuard, ModbusError] {
  if max_peers < 1 || max_events < 1 {
    Err(InvalidData)
  } else {
    Ok({ policy, peers: [], events: [], max_peers, max_events, sequence: 0 })
  }
}

///|
pub fn ProtocolGuard::peer_count(self : ProtocolGuard) -> Int {
  self.peers.length()
}

///|
pub fn ProtocolGuard::event_count(self : ProtocolGuard) -> Int {
  self.events.length()
}

///|
pub fn ProtocolGuard::policy(self : ProtocolGuard) -> ProtocolGuardPolicy {
  self.policy
}

///|
fn ProtocolGuard::peer(self : ProtocolGuard, name : String) -> PeerGuardState? {
  for peer in self.peers {
    if peer.peer() == name {
      return Some(peer)
    }
  }
  None
}

///|
fn ProtocolGuard::get_or_create_peer(
  self : ProtocolGuard,
  name : String,
) -> Result[PeerGuardState, ModbusError] {
  match self.peer(name) {
    Some(peer) => Ok(peer)
    None => {
      if self.peers.length() >= self.max_peers {
        return Err(CapacityExceeded)
      }
      let peer = match PeerGuardState::new(name) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.peers.push(peer)
      Ok(peer)
    }
  }
}

///|
/// Validate and record a frame before transport-specific decoding.
pub fn ProtocolGuard::admit(
  self : ProtocolGuard,
  peer_name : String,
  frame : Frame,
  now : Int,
) -> Result[GuardDecision, ModbusError] {
  if peer_name == "" || now < 0 {
    return Err(InvalidData)
  }
  let peer = match self.get_or_create_peer(peer_name) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ignore(peer.prune(now, self.policy))
  let fingerprint = FrameFingerprint::from_frame(frame)
  let mut decision = AdmitFrame
  let mut reason = GuardAccepted
  if !is_valid_unit_id(frame.unit_id, broadcast=self.policy.allow_broadcast) {
    decision = RejectFrame
    reason = GuardBadUnit
  } else if !self.policy.function_allowed(frame.pdu.function) {
    decision = RejectFrame
    reason = GuardBadFunction
  } else if frame.pdu.data.length() + 2 > self.policy.max_frame_bytes {
    decision = OversizeFrame
    reason = GuardTooLarge
  } else if peer.duplicate(fingerprint, now, self.policy) {
    decision = DuplicateFrame
    reason = GuardDuplicate
  } else if peer.frame_count() >= self.policy.max_frames() {
    decision = QuotaFrame
    reason = GuardRateLimited
  }
  let accepted = decision == AdmitFrame
  peer.record(fingerprint, now, accepted)
  self.sequence += 1
  if self.events.length() >= self.max_events {
    ignore(self.events.remove(0))
  }
  match
    GuardEvent::new(self.sequence, now, peer_name, decision, reason, frame) {
    Ok(event) => self.events.push(event)
    Err(_) => ()
  }
  Ok(decision)
}

///|
pub fn ProtocolGuard::recent_events(
  self : ProtocolGuard,
  limit : Int,
) -> Result[Array[GuardEvent], ModbusError] {
  if limit < 1 {
    return Err(InvalidQuantity)
  }
  let result : Array[GuardEvent] = []
  let start = if self.events.length() > limit {
    self.events.length() - limit
  } else {
    0
  }
  for i in start..<self.events.length() {
    result.push(self.events[i])
  }
  Ok(result)
}

///|
pub fn ProtocolGuard::peer_stats(
  self : ProtocolGuard,
  name : String,
) -> Result[(Int, Int), ModbusError] {
  match self.peer(name) {
    Some(peer) => Ok((peer.accepted(), peer.rejected()))
    None => Err(InvalidData)
  }
}

///|
pub fn ProtocolGuard::decision_counts(self : ProtocolGuard) -> Array[Int] {
  let counts : Array[Int] = [0, 0, 0, 0, 0, 0]
  for event in self.events {
    let index = match event.decision() {
      AdmitFrame => 0
      RejectFrame => 1
      DeferFrame => 2
      DuplicateFrame => 3
      QuotaFrame => 4
      OversizeFrame => 5
    }
    counts[index] += 1
  }
  counts
}

///|
/// Flush historical events while retaining peer counters.
pub fn ProtocolGuard::clear_events(self : ProtocolGuard) -> Unit {
  self.events.clear()
}
