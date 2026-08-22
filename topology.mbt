///|
/// The role of a node in a Modbus deployment topology.
pub(all) enum TopologyNodeKind {
  SiteNode
  DeviceNode
  GatewayNode
  ServiceNode
} derive(Debug, Eq)

///|
/// Operational health used by route selection and dashboards.
pub(all) enum TopologyHealth {
  Healthy
  Degraded
  Unreachable
  Maintenance
  UnknownHealth
} derive(Debug, Eq)

///|
/// A graph node representing a site, device, gateway, or consumer.
pub(all) struct TopologyNode {
  id : String
  label : String
  kind : TopologyNodeKind
  unit_id : Byte?
  mut health : TopologyHealth
  mut load : Int
  zone : String
  tags : Array[String]
}

///|
pub fn TopologyNode::new(
  id : String,
  label : String,
  kind : TopologyNodeKind,
  unit_id? : Byte = 0,
  zone? : String = "",
) -> Result[TopologyNode, ModbusError] {
  if id == "" || label == "" {
    return Err(InvalidData)
  }
  if unit_id != 0 && !is_valid_unit_id(unit_id) {
    return Err(InvalidUnitId)
  }
  let selected_unit = if unit_id == 0 { None } else { Some(unit_id) }
  Ok({
    id,
    label,
    kind,
    unit_id: selected_unit,
    health: UnknownHealth,
    load: 0,
    zone,
    tags: [],
  })
}

///|
pub fn TopologyNode::id(self : TopologyNode) -> String {
  self.id
}

///|
pub fn TopologyNode::label(self : TopologyNode) -> String {
  self.label
}

///|
pub fn TopologyNode::kind(self : TopologyNode) -> TopologyNodeKind {
  self.kind
}

///|
pub fn TopologyNode::unit_id(self : TopologyNode) -> Byte? {
  self.unit_id
}

///|
pub fn TopologyNode::health(self : TopologyNode) -> TopologyHealth {
  self.health
}

///|
pub fn TopologyNode::load(self : TopologyNode) -> Int {
  self.load
}

///|
pub fn TopologyNode::zone(self : TopologyNode) -> String {
  self.zone
}

///|
pub fn TopologyNode::set_health(
  self : TopologyNode,
  health : TopologyHealth,
) -> Unit {
  self.health = health
}

///|
pub fn TopologyNode::set_load(
  self : TopologyNode,
  load : Int,
) -> Result[Unit, ModbusError] {
  if load < 0 || load > 100 {
    Err(InvalidData)
  } else {
    self.load = load
    Ok(())
  }
}

///|
pub fn TopologyNode::add_tag(
  self : TopologyNode,
  tag : String,
) -> Result[Unit, ModbusError] {
  if tag == "" {
    return Err(InvalidData)
  }
  for existing in self.tags {
    if existing == tag {
      return Ok(())
    }
  }
  self.tags.push(tag)
  Ok(())
}

///|
pub fn TopologyNode::has_tag(self : TopologyNode, tag : String) -> Bool {
  for existing in self.tags {
    if existing == tag {
      return true
    }
  }
  false
}

///|
pub fn TopologyNode::tag_count(self : TopologyNode) -> Int {
  self.tags.length()
}

///|
pub fn TopologyNode::is_available(self : TopologyNode) -> Bool {
  self.health == Healthy || self.health == Degraded
}

///|
pub fn topology_node_kind_name(kind : TopologyNodeKind) -> String {
  match kind {
    SiteNode => "site"
    DeviceNode => "device"
    GatewayNode => "gateway"
    ServiceNode => "service"
  }
}

///|
pub fn topology_health_name(health : TopologyHealth) -> String {
  match health {
    Healthy => "healthy"
    Degraded => "degraded"
    Unreachable => "unreachable"
    Maintenance => "maintenance"
    UnknownHealth => "unknown"
  }
}

///|
/// A directed or bidirectional connection between topology nodes.
pub(all) struct TopologyLink {
  id : String
  from : String
  to : String
  latency : Int
  capacity : Int
  mut utilization : Int
  bidirectional : Bool
  transport : String
}

///|
pub fn TopologyLink::new(
  id : String,
  from : String,
  to : String,
  latency : Int,
  capacity : Int,
  bidirectional? : Bool = true,
  transport? : String = "modbus",
) -> Result[TopologyLink, ModbusError] {
  if id == "" || from == "" || to == "" || from == to {
    return Err(InvalidData)
  }
  if latency < 0 || capacity < 1 {
    return Err(InvalidData)
  }
  if transport == "" {
    return Err(InvalidData)
  }
  Ok({
    id,
    from,
    to,
    latency,
    capacity,
    utilization: 0,
    bidirectional,
    transport,
  })
}

///|
pub fn TopologyLink::id(self : TopologyLink) -> String {
  self.id
}

///|
pub fn TopologyLink::from(self : TopologyLink) -> String {
  self.from
}

///|
pub fn TopologyLink::to(self : TopologyLink) -> String {
  self.to
}

///|
pub fn TopologyLink::latency(self : TopologyLink) -> Int {
  self.latency
}

///|
pub fn TopologyLink::capacity(self : TopologyLink) -> Int {
  self.capacity
}

///|
pub fn TopologyLink::utilization(self : TopologyLink) -> Int {
  self.utilization
}

///|
pub fn TopologyLink::transport(self : TopologyLink) -> String {
  self.transport
}

///|
pub fn TopologyLink::is_bidirectional(self : TopologyLink) -> Bool {
  self.bidirectional
}

///|
pub fn TopologyLink::set_utilization(
  self : TopologyLink,
  value : Int,
) -> Result[Unit, ModbusError] {
  if value < 0 || value > 100 {
    Err(InvalidData)
  } else {
    self.utilization = value
    Ok(())
  }
}

///|
pub fn TopologyLink::available(self : TopologyLink) -> Bool {
  self.utilization < 100
}

///|
pub fn TopologyLink::cost(self : TopologyLink) -> Int {
  self.latency + self.utilization + 100 / self.capacity
}

///|
pub fn TopologyLink::connects(self : TopologyLink, node_id : String) -> Bool {
  self.from == node_id || (self.bidirectional && self.to == node_id)
}

///|
pub fn TopologyLink::other(self : TopologyLink, node_id : String) -> String? {
  if self.from == node_id {
    Some(self.to)
  } else if self.bidirectional && self.to == node_id {
    Some(self.from)
  } else {
    None
  }
}

///|
/// A selected path with aggregate latency and link identifiers.
pub(all) struct TopologyRoute {
  source : String
  destination : String
  nodes : Array[String]
  links : Array[String]
  cost : Int
  reachable : Bool
}

///|
pub fn TopologyRoute::not_reachable(
  source : String,
  destination : String,
) -> TopologyRoute {
  { source, destination, nodes: [], links: [], cost: 0, reachable: false }
}

///|
pub fn TopologyRoute::new(
  source : String,
  destination : String,
  nodes : Array[String],
  links : Array[String],
  cost : Int,
) -> TopologyRoute {
  { source, destination, nodes, links, cost, reachable: true }
}

///|
pub fn TopologyRoute::source(self : TopologyRoute) -> String {
  self.source
}

///|
pub fn TopologyRoute::destination(self : TopologyRoute) -> String {
  self.destination
}

///|
pub fn TopologyRoute::nodes(self : TopologyRoute) -> Array[String] {
  self.nodes
}

///|
pub fn TopologyRoute::links(self : TopologyRoute) -> Array[String] {
  self.links
}

///|
pub fn TopologyRoute::cost(self : TopologyRoute) -> Int {
  self.cost
}

///|
pub fn TopologyRoute::reachable(self : TopologyRoute) -> Bool {
  self.reachable
}

///|
pub fn TopologyRoute::hops(self : TopologyRoute) -> Int {
  if self.nodes.length() == 0 {
    0
  } else {
    self.nodes.length() - 1
  }
}

///|
pub fn TopologyRoute::summary(self : TopologyRoute) -> String {
  self.source +
  "->" +
  self.destination +
  " hops=" +
  self.hops().to_string() +
  " cost=" +
  self.cost.to_string() +
  " reachable=" +
  self.reachable.to_string()
}

///|
/// A mutable topology graph used by gateway routing and deployment tools.
pub(all) struct NetworkTopology {
  nodes : Array[TopologyNode]
  links : Array[TopologyLink]
  max_nodes : Int
  max_links : Int
}

///|
pub fn NetworkTopology::new(
  max_nodes? : Int = 1024,
  max_links? : Int = 4096,
) -> Result[NetworkTopology, ModbusError] {
  if max_nodes < 1 || max_links < 1 {
    Err(InvalidData)
  } else {
    Ok({ nodes: [], links: [], max_nodes, max_links })
  }
}

///|
pub fn NetworkTopology::node_count(self : NetworkTopology) -> Int {
  self.nodes.length()
}

///|
pub fn NetworkTopology::link_count(self : NetworkTopology) -> Int {
  self.links.length()
}

///|
pub fn NetworkTopology::max_nodes(self : NetworkTopology) -> Int {
  self.max_nodes
}

///|
pub fn NetworkTopology::max_links(self : NetworkTopology) -> Int {
  self.max_links
}

///|
pub fn NetworkTopology::has_node(self : NetworkTopology, id : String) -> Bool {
  for node in self.nodes {
    if node.id() == id {
      return true
    }
  }
  false
}

///|
pub fn NetworkTopology::node(
  self : NetworkTopology,
  id : String,
) -> TopologyNode? {
  for node in self.nodes {
    if node.id() == id {
      return Some(node)
    }
  }
  None
}

///|
pub fn NetworkTopology::add_node(
  self : NetworkTopology,
  node : TopologyNode,
) -> Result[Unit, ModbusError] {
  if self.nodes.length() >= self.max_nodes {
    return Err(CapacityExceeded)
  }
  if self.has_node(node.id()) {
    return Err(InvalidData)
  }
  self.nodes.push(node)
  Ok(())
}

///|
pub fn NetworkTopology::remove_node(
  self : NetworkTopology,
  id : String,
) -> Result[TopologyNode, ModbusError] {
  let mut index = -1
  for i in 0..<self.nodes.length() {
    if self.nodes[i].id() == id {
      index = i
      break
    }
  }
  if index < 0 {
    return Err(InvalidData)
  }
  for link in self.links {
    if link.connects(id) {
      return Err(Busy)
    }
  }
  Ok(self.nodes.remove(index))
}

///|
pub fn NetworkTopology::add_link(
  self : NetworkTopology,
  link : TopologyLink,
) -> Result[Unit, ModbusError] {
  if self.links.length() >= self.max_links {
    return Err(CapacityExceeded)
  }
  if !self.has_node(link.from()) || !self.has_node(link.to()) {
    return Err(UnitMismatch)
  }
  for existing in self.links {
    if existing.id() == link.id() {
      return Err(InvalidData)
    }
  }
  self.links.push(link)
  Ok(())
}

///|
pub fn NetworkTopology::link(
  self : NetworkTopology,
  id : String,
) -> TopologyLink? {
  for link in self.links {
    if link.id() == id {
      return Some(link)
    }
  }
  None
}

///|
pub fn NetworkTopology::set_node_health(
  self : NetworkTopology,
  id : String,
  health : TopologyHealth,
) -> Result[Unit, ModbusError] {
  for node in self.nodes {
    if node.id() == id {
      node.set_health(health)
      return Ok(())
    }
  }
  Err(InvalidData)
}

///|
pub fn NetworkTopology::set_link_utilization(
  self : NetworkTopology,
  id : String,
  utilization : Int,
) -> Result[Unit, ModbusError] {
  for link in self.links {
    if link.id() == id {
      return link.set_utilization(utilization)
    }
  }
  Err(InvalidData)
}

///|
fn NetworkTopology::topology_node_available(
  self : NetworkTopology,
  id : String,
  source : String,
  destination : String,
) -> Bool {
  if id == source || id == destination {
    return true
  }
  match self.node(id) {
    Some(node) => node.is_available()
    None => false
  }
}

///|
/// Find a low-cost path with a bounded Bellman-Ford relaxation.
pub fn NetworkTopology::route(
  self : NetworkTopology,
  source : String,
  destination : String,
) -> Result[TopologyRoute, ModbusError] {
  if !self.has_node(source) || !self.has_node(destination) {
    return Err(InvalidData)
  }
  if source == destination {
    return Ok(TopologyRoute::new(source, destination, [source], [], 0))
  }
  let count = self.nodes.length()
  let distances : Array[Int] = []
  let previous : Array[String?] = []
  let previous_link : Array[String?] = []
  for _ in 0..<count {
    distances.push(1_000_000_000)
    previous.push(None)
    previous_link.push(None)
  }
  let source_index = self.node_index(source)
  distances[source_index] = 0
  for _ in 0..<count {
    let mut changed = false
    for from_index in 0..<count {
      if distances[from_index] >= 1_000_000_000 {
        continue
      }
      let from_id = self.nodes[from_index].id()
      for link in self.links {
        let target = if link.from() == from_id && link.available() {
          Some(link.to())
        } else if link.is_bidirectional() &&
          link.to() == from_id &&
          link.available() {
          Some(link.from())
        } else {
          None
        }
        match target {
          None => ()
          Some(target_id) => {
            if !self.topology_node_available(target_id, source, destination) {
              continue
            }
            let target_index = self.node_index(target_id)
            let candidate = distances[from_index] + link.cost()
            if candidate < distances[target_index] {
              distances[target_index] = candidate
              previous[target_index] = Some(from_id)
              previous_link[target_index] = Some(link.id())
              changed = true
            }
          }
        }
      }
    }
    if !changed {
      break
    }
  }
  let destination_index = self.node_index(destination)
  if distances[destination_index] >= 1_000_000_000 {
    return Ok(TopologyRoute::not_reachable(source, destination))
  }
  let mut path_nodes : Array[String] = []
  let mut path_links : Array[String] = []
  let mut current = destination
  path_nodes.push(current)
  while current != source {
    let index = self.node_index(current)
    match previous_link[index] {
      Some(link_id) => path_links.push(link_id)
      None => return Ok(TopologyRoute::not_reachable(source, destination))
    }
    match previous[index] {
      Some(node_id) => {
        current = node_id
        path_nodes.push(current)
      }
      None => return Ok(TopologyRoute::not_reachable(source, destination))
    }
  }
  path_nodes = topology_reverse_strings(path_nodes)
  path_links = topology_reverse_strings(path_links)
  Ok(
    TopologyRoute::new(
      source,
      destination,
      path_nodes,
      path_links,
      distances[destination_index],
    ),
  )
}

///|
fn topology_reverse_strings(values : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for i in 0..<values.length() {
    result.push(values[values.length() - i - 1])
  }
  result
}

///|
fn NetworkTopology::node_index(self : NetworkTopology, id : String) -> Int {
  for i in 0..<self.nodes.length() {
    if self.nodes[i].id() == id {
      return i
    }
  }
  0
}

///|
/// Return all nodes whose health is not currently healthy.
pub fn NetworkTopology::unhealthy_nodes(
  self : NetworkTopology,
) -> Array[String] {
  let result : Array[String] = []
  for node in self.nodes {
    if node.health() != Healthy {
      result.push(node.id())
    }
  }
  result
}

///|
/// Return links at or above a utilization threshold.
pub fn NetworkTopology::busy_links(
  self : NetworkTopology,
  threshold : Int,
) -> Result[Array[String], ModbusError] {
  if threshold < 0 || threshold > 100 {
    return Err(InvalidData)
  }
  let result : Array[String] = []
  for link in self.links {
    if link.utilization() >= threshold {
      result.push(link.id())
    }
  }
  Ok(result)
}

///|
/// Validate graph references, duplicate identifiers, and unit assignments.
pub fn NetworkTopology::validate(self : NetworkTopology) -> Array[ModbusError] {
  let errors : Array[ModbusError] = []
  for i in 0..<self.nodes.length() {
    for j in (i + 1)..<self.nodes.length() {
      if self.nodes[i].id() == self.nodes[j].id() {
        errors.push(InvalidData)
      }
    }
    match self.nodes[i].unit_id() {
      Some(unit_id) =>
        if !is_valid_unit_id(unit_id) {
          errors.push(InvalidUnitId)
        }
      None => ()
    }
  }
  for link in self.links {
    if !self.has_node(link.from()) || !self.has_node(link.to()) {
      errors.push(UnitMismatch)
    }
    if link.utilization() > 100 {
      errors.push(InvalidData)
    }
  }
  errors
}

///|
/// A compact health report suitable for a gateway status endpoint.
pub(all) struct TopologyHealthReport {
  node_count : Int
  link_count : Int
  healthy : Int
  degraded : Int
  unavailable : Int
  average_load : Int
  invalid_edges : Int
}

///|
pub fn TopologyHealthReport::new(
  topology : NetworkTopology,
) -> TopologyHealthReport {
  let mut healthy = 0
  let mut degraded = 0
  let mut unavailable = 0
  let mut load = 0
  for node in topology.nodes {
    load += node.load()
    match node.health() {
      Healthy => healthy += 1
      Degraded => degraded += 1
      Unreachable | Maintenance | UnknownHealth => unavailable += 1
    }
  }
  let invalid_edges = topology.validate().length()
  {
    node_count: topology.node_count(),
    link_count: topology.link_count(),
    healthy,
    degraded,
    unavailable,
    average_load: if topology.node_count() == 0 {
      0
    } else {
      load / topology.node_count()
    },
    invalid_edges,
  }
}

///|
pub fn TopologyHealthReport::node_count(self : TopologyHealthReport) -> Int {
  self.node_count
}

///|
pub fn TopologyHealthReport::link_count(self : TopologyHealthReport) -> Int {
  self.link_count
}

///|
pub fn TopologyHealthReport::healthy(self : TopologyHealthReport) -> Int {
  self.healthy
}

///|
pub fn TopologyHealthReport::degraded(self : TopologyHealthReport) -> Int {
  self.degraded
}

///|
pub fn TopologyHealthReport::unavailable(self : TopologyHealthReport) -> Int {
  self.unavailable
}

///|
pub fn TopologyHealthReport::average_load(self : TopologyHealthReport) -> Int {
  self.average_load
}

///|
pub fn TopologyHealthReport::invalid_edges(self : TopologyHealthReport) -> Int {
  self.invalid_edges
}

///|
pub fn TopologyHealthReport::summary(self : TopologyHealthReport) -> String {
  "nodes=" +
  self.node_count.to_string() +
  " links=" +
  self.link_count.to_string() +
  " healthy=" +
  self.healthy.to_string() +
  " degraded=" +
  self.degraded.to_string() +
  " unavailable=" +
  self.unavailable.to_string() +
  " load=" +
  self.average_load.to_string()
}
