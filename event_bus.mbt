///|
/// Application event categories emitted by the protocol services.
pub(all) enum ServiceEventKind {
  FrameReceivedEvent
  FrameSentEvent
  AlarmRaisedEvent
  AlarmClearedEvent
  CommandUpdatedEvent
  DeviceHealthEvent
  MaintenanceDueEvent
  GatewayDeniedEvent
} derive(Debug, Eq)

///|
/// Delivery state used by durable event consumers.
pub(all) enum EventDelivery {
  EventPending
  EventDelivered
  EventFailed
  EventDeadLetter
} derive(Debug, Eq)

///|
/// Small immutable event envelope suitable for an in-memory or file queue.
pub(all) struct ServiceEvent {
  id : String
  kind : ServiceEventKind
  source : String
  timestamp : Int
  payload : Array[Byte]
  mut delivery : EventDelivery
  mut attempts : Int
}

///|
pub fn ServiceEvent::new(
  id : String,
  kind : ServiceEventKind,
  source : String,
  timestamp : Int,
  payload : Array[Byte],
) -> Result[ServiceEvent, ModbusError] {
  if id == "" || source == "" || timestamp < 0 || payload.length() > 65535 {
    return Err(InvalidData)
  }
  Ok({
    id,
    kind,
    source,
    timestamp,
    payload: payload.copy(),
    delivery: EventPending,
    attempts: 0,
  })
}

///|
pub fn ServiceEvent::id(self : ServiceEvent) -> String {
  self.id
}

///|
pub fn ServiceEvent::kind(self : ServiceEvent) -> ServiceEventKind {
  self.kind
}

///|
pub fn ServiceEvent::source(self : ServiceEvent) -> String {
  self.source
}

///|
pub fn ServiceEvent::timestamp(self : ServiceEvent) -> Int {
  self.timestamp
}

///|
pub fn ServiceEvent::payload(self : ServiceEvent) -> Array[Byte] {
  self.payload.copy()
}

///|
pub fn ServiceEvent::delivery(self : ServiceEvent) -> EventDelivery {
  self.delivery
}

///|
pub fn ServiceEvent::attempts(self : ServiceEvent) -> Int {
  self.attempts
}

///|
pub fn ServiceEvent::mark_delivered(self : ServiceEvent) -> Unit {
  self.delivery = EventDelivered
}

///|
pub fn ServiceEvent::mark_failed(
  self : ServiceEvent,
  dead_letter_after : Int,
) -> Result[Unit, ModbusError] {
  if dead_letter_after < 1 {
    return Err(InvalidData)
  }
  self.attempts += 1
  self.delivery = if self.attempts >= dead_letter_after {
    EventDeadLetter
  } else {
    EventFailed
  }
  Ok(())
}

///|
pub fn service_event_kind_name(kind : ServiceEventKind) -> String {
  match kind {
    FrameReceivedEvent => "frame-received"
    FrameSentEvent => "frame-sent"
    AlarmRaisedEvent => "alarm-raised"
    AlarmClearedEvent => "alarm-cleared"
    CommandUpdatedEvent => "command-updated"
    DeviceHealthEvent => "device-health"
    MaintenanceDueEvent => "maintenance-due"
    GatewayDeniedEvent => "gateway-denied"
  }
}

///|
/// Subscription filter for one consumer.
pub(all) struct EventSubscription {
  id : String
  source : String?
  kind : ServiceEventKind?
  mut enabled : Bool
}

///|
pub fn EventSubscription::new(
  id : String,
  source? : String = "",
  kind? : ServiceEventKind = FrameReceivedEvent,
) -> Result[EventSubscription, ModbusError] {
  if id == "" {
    return Err(InvalidData)
  }
  let selected_source = if source == "" { None } else { Some(source) }
  let selected_kind = if source == "" { None } else { Some(kind) }
  Ok({ id, source: selected_source, kind: selected_kind, enabled: true })
}

///|
pub fn EventSubscription::id(self : EventSubscription) -> String {
  self.id
}

///|
pub fn EventSubscription::enabled(self : EventSubscription) -> Bool {
  self.enabled
}

///|
pub fn EventSubscription::set_enabled(
  self : EventSubscription,
  enabled : Bool,
) -> Unit {
  self.enabled = enabled
}

///|
pub fn EventSubscription::matches(
  self : EventSubscription,
  event : ServiceEvent,
) -> Bool {
  if !self.enabled {
    return false
  }
  let source_ok = match self.source {
    Some(source) => source == event.source()
    None => true
  }
  let kind_ok = match self.kind {
    Some(kind) => kind == event.kind()
    None => true
  }
  source_ok && kind_ok
}

///|
/// Event queue with bounded pending and dead-letter retention.
pub(all) struct ServiceEventBus {
  queue : Array[ServiceEvent]
  dead_letters : Array[ServiceEvent]
  subscriptions : Array[EventSubscription]
  max_queue : Int
  max_dead_letters : Int
  max_subscriptions : Int
}

///|
pub fn ServiceEventBus::new(
  max_queue? : Int = 8192,
  max_dead_letters? : Int = 1024,
  max_subscriptions? : Int = 256,
) -> Result[ServiceEventBus, ModbusError] {
  if max_queue < 1 || max_dead_letters < 1 || max_subscriptions < 1 {
    Err(InvalidData)
  } else {
    Ok({
      queue: [],
      dead_letters: [],
      subscriptions: [],
      max_queue,
      max_dead_letters,
      max_subscriptions,
    })
  }
}

///|
pub fn ServiceEventBus::queue_count(self : ServiceEventBus) -> Int {
  self.queue.length()
}

///|
pub fn ServiceEventBus::dead_letter_count(self : ServiceEventBus) -> Int {
  self.dead_letters.length()
}

///|
pub fn ServiceEventBus::subscription_count(self : ServiceEventBus) -> Int {
  self.subscriptions.length()
}

///|
pub fn ServiceEventBus::subscribe(
  self : ServiceEventBus,
  subscription : EventSubscription,
) -> Result[Unit, ModbusError] {
  if self.subscriptions.length() >= self.max_subscriptions {
    return Err(CapacityExceeded)
  }
  for existing in self.subscriptions {
    if existing.id() == subscription.id() {
      return Err(InvalidData)
    }
  }
  self.subscriptions.push(subscription)
  Ok(())
}

///|
pub fn ServiceEventBus::unsubscribe(
  self : ServiceEventBus,
  id : String,
) -> Result[EventSubscription, ModbusError] {
  for i in 0..<self.subscriptions.length() {
    if self.subscriptions[i].id() == id {
      return Ok(self.subscriptions.remove(i))
    }
  }
  Err(InvalidData)
}

///|
/// Publish an event and enforce the queue capacity.
pub fn ServiceEventBus::publish(
  self : ServiceEventBus,
  event : ServiceEvent,
) -> Result[Unit, ModbusError] {
  for existing in self.queue {
    if existing.id() == event.id() {
      return Err(InvalidData)
    }
  }
  if self.queue.length() >= self.max_queue {
    return Err(CapacityExceeded)
  }
  self.queue.push(event)
  Ok(())
}

///|
/// Claim the next event matching a subscription.
pub fn ServiceEventBus::claim(
  self : ServiceEventBus,
  subscription_id : String,
) -> Result[ServiceEvent, ModbusError] {
  let subscription = match self.find_subscription(subscription_id) {
    Some(value) => value
    None => return Err(InvalidData)
  }
  for i in 0..<self.queue.length() {
    if subscription.matches(self.queue[i]) {
      return Ok(self.queue.remove(i))
    }
  }
  Err(Incomplete)
}

///|
fn ServiceEventBus::find_subscription(
  self : ServiceEventBus,
  id : String,
) -> EventSubscription? {
  for subscription in self.subscriptions {
    if subscription.id() == id {
      return Some(subscription)
    }
  }
  None
}

///|
/// Acknowledge an event or return it to the queue after a failed attempt.
pub fn ServiceEventBus::ack(
  self : ServiceEventBus,
  event : ServiceEvent,
  success : Bool,
  dead_letter_after? : Int = 3,
) -> Result[Unit, ModbusError] {
  if success {
    event.mark_delivered()
    Ok(())
  } else {
    match event.mark_failed(dead_letter_after) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match event.delivery() {
      EventDeadLetter => {
        if self.dead_letters.length() >= self.max_dead_letters {
          ignore(self.dead_letters.remove(0))
        }
        self.dead_letters.push(event)
        Ok(())
      }
      _ => self.publish(event)
    }
  }
}

///|
/// Return events filtered by kind without claiming them.
pub fn ServiceEventBus::peek_kind(
  self : ServiceEventBus,
  kind : ServiceEventKind,
) -> Array[ServiceEvent] {
  let result : Array[ServiceEvent] = []
  for event in self.queue {
    if event.kind() == kind {
      result.push(event)
    }
  }
  result
}

///|
pub fn ServiceEventBus::clear_dead_letters(self : ServiceEventBus) -> Unit {
  self.dead_letters.clear()
}
