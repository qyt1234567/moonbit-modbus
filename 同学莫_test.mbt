///|
test "crc16 known vector" {
  let crc = crc16([1, 3, 0, 0, 0, 10])
  inspect(crc.to_string(radix=16), content="cdc5")
  inspect(crc16_update(0xFFFF, 1) != 0, content="true")
}

///|
test "rtu round trip" {
  let bytes = encode_rtu(read_holding(1, 0, 10))
  inspect(decode_rtu(bytes) is Ok(_), content="true")
  let corrupt = bytes.copy()
  corrupt[corrupt.length() - 1] = corrupt[corrupt.length() - 1] ^ 1
  inspect(decode_rtu(corrupt) is Err(InvalidChecksum), content="true")
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
  let bad = bytes.copy()
  bad[2] = 1
  inspect(decode_tcp(bad) is Err(InvalidMbap), content="true")
}

///|
test "ascii round trip and hex" {
  let frame = read_holding(1, 16, 2)
  inspect(decode_ascii(encode_ascii(frame)) is Ok(_), content="true")
  inspect(bytes_to_hex_string([0, 1, 0xAB, 0xFF]), content="0001ABFF")
  inspect(hex_string_to_bytes("00 01 ab ff") is Ok(_), content="true")
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
  let words = u32_to_registers(0x12345678, HighWordFirst)
  inspect(
    registers_to_u32(words, HighWordFirst).unwrap().to_string(radix=16),
    content="12345678",
  )
  let float = registers_to_f32(
    f32_to_registers(1.5, HighWordFirst),
    HighWordFirst,
  ).unwrap()
  assert_true(float.is_close(1.5))
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

///|
test "builder boundaries" {
  inspect(read_coils(1, 0, 1) is Ok(_), content="true")
  inspect(read_coils(1, 0, 2000) is Ok(_), content="true")
  inspect(read_coils(1, 0, 2001) is Err(InvalidQuantity), content="true")
  inspect(read_input_registers(1, 0, 125) is Ok(_), content="true")
  inspect(
    read_input_registers(1, 0, 126) is Err(InvalidQuantity),
    content="true",
  )
  inspect(read_coils(248, 0, 1) is Err(InvalidUnitId), content="true")
  inspect(
    read_holding_checked(1, 65535, 2) is Err(InvalidAddress),
    content="true",
  )
  inspect(
    write_multiple_registers(1, 0, []) is Err(InvalidQuantity),
    content="true",
  )
  inspect(
    write_multiple_coils(1, 0, []) is Err(InvalidQuantity),
    content="true",
  )
}

///|
test "coil packing and vector operations" {
  let values : Array[Bool] = [
    true, false, true, false, false, false, false, true, true,
  ]
  let packed = pack_bits(values)
  debug_inspect(packed, content="[0x85, 0x01]")
  debug_inspect(
    unpack_bits(packed, 9).unwrap(),
    content="[true, false, true, false, false, false, false, true, true]",
  )
  let vector = BitVector::from_bits(values)
  inspect(vector.count(), content="4")
  inspect(vector.get(7).unwrap(), content="true")
  ignore(vector.set(1, true))
  inspect(vector.count(), content="5")
  inspect(vector.not().count(), content="4")
  inspect(vector.shift_left(1).unwrap().get(1).unwrap(), content="true")
}

///|
test "register cursor and writer boundaries" {
  let cursor = RegisterCursor::new([1, 0xFFFF, 0, 0x1234])
  inspect(cursor.read_u16().unwrap(), content="1")
  inspect(cursor.read_i16().unwrap(), content="-1")
  inspect(cursor.remaining(), content="2")
  inspect(
    cursor.read_u32(HighWordFirst).unwrap().to_string(radix=16),
    content="1234",
  )
  inspect(cursor.read_u16() is Err(Incomplete), content="true")
  let writer = RegisterWriter::new(2).unwrap()
  ignore(writer.push(10))
  ignore(writer.push(20))
  inspect(writer.push(30) is Err(CapacityExceeded), content="true")
  debug_inspect(writer.to_array(), content="[10, 20]")
}

///|
test "incremental parser chunking" {
  let frame = read_holding(1, 0, 2)
  let wire = encode_rtu(frame)
  let parser = IncrementalParser::new(Rtu, role=Request)
  let first = parser.feed(wire[:3].to_owned()).unwrap()
  inspect(first.length(), content="0")
  let second = parser.feed(wire[3:].to_owned()).unwrap()
  inspect(second.length(), content="1")
  inspect(parser.buffered(), content="0")
  inspect(parser.frames_seen(), content="1")
}

///|
test "tcp stream parses multiple frames" {
  let first = encode_tcp(1, read_holding(1, 0, 1))
  let second = encode_tcp(2, read_holding(1, 1, 1))
  let input = first.add(second)
  let parser = IncrementalParser::new(Tcp, role=Response)
  let frames = parser.feed(input).unwrap()
  inspect(frames.length(), content="2")
  inspect(parser.buffered(), content="0")
  let chunks = chunk_bytes(input, 3).unwrap()
  let stream = FrameStream::new(Tcp, role=Response).unwrap()
  let mut count = 0
  for chunk in chunks {
    count += stream.push(chunk).unwrap().length()
  }
  inspect(count, content="2")
}

///|
test "device register read and write" {
  let device = Device::new(1, coil_capacity=32, register_capacity=16).unwrap()
  ignore(device.memory().load_holding(0, [100, 200, 300]))
  let read = read_holding_registers(1, 0, 3).unwrap()
  let response = device.handle(read).unwrap()
  debug_inspect(
    decode_register_response(read, response).unwrap(),
    content="[100, 200, 300]",
  )
  let write = write_single_register(1, 1, 999)
  let write_response = device.handle(write).unwrap()
  inspect(
    decode_write_single_register(write, write_response).unwrap(),
    content="999",
  )
  inspect(device.memory().holding_registers().get(1).unwrap(), content="999")
}

///|
test "device coils and broadcast" {
  let device = Device::new(2, coil_capacity=16, register_capacity=8).unwrap()
  let write = write_single_coil(2, 3, true).unwrap()
  ignore(device.handle(write))
  inspect(device.memory().coils().get(3).unwrap(), content="true")
  let read = read_coils(2, 0, 8).unwrap()
  let response = device.handle(read).unwrap()
  inspect(decode_bits_response(read, response).unwrap()[3], content="true")
  let broadcast = write_single_register(0, 0, 1)
  inspect(device.serve(broadcast).unwrap() is NoReply, content="true")
}

///|
test "device exceptions and health" {
  let device = Device::new(1).unwrap()
  let unsupported = Frame::new(1, 99, [])
  let response = device.handle(unsupported).unwrap()
  inspect(response.is_exception(), content="true")
  debug_inspect(
    exception_from_frame(response).unwrap(),
    content="IllegalFunction",
  )
  inspect(device.exception_count(), content="1")
  device.set_busy(true)
  let read = read_holding(1, 0, 1)
  inspect(device.handle(read).unwrap().is_exception(), content="true")
  inspect(device.health().busy, content="true")
}

///|
test "client transaction correlation" {
  let device = Device::new(1).unwrap()
  let client = Client::new(Tcp)
  let frame = read_holding(1, 0, 1)
  let request = client.begin(frame).unwrap()
  let response = device.handle(frame).unwrap()
  inspect(
    client.accept_frame(request, request.transaction_id, response) is Ok(_),
    content="true",
  )
  inspect(client.completed_count(), content="1")
  let second = client.begin(frame).unwrap()
  let wrong = client.accept_frame(second, 999, response)
  inspect(wrong is Err(InvalidTransaction), content="true")
  inspect(client.failed_count(), content="1")
}

///|
test "poll plan and batch execution" {
  let device = Device::new(1).unwrap()
  let plan = PollPlan::new().unwrap()
  let job = PollJob::new(1, "temperature", read_holding(1, 0, 1)).unwrap()
  ignore(plan.add(job))
  inspect(validate_poll_plan(plan) is Ok(_), content="true")
  let report = plan.run_once(device, 0)
  inspect(report.attempted, content="1")
  inspect(report.succeeded, content="1")
  let batch = BatchPlan::new().unwrap()
  ignore(batch.add(BatchItem::new(1, read_holding(1, 0, 1)).unwrap()))
  ignore(batch.add(BatchItem::new(2, read_holding(1, 1, 1)).unwrap()))
  let results = batch.execute(device)
  inspect(batch_completed(results), content="2")
}

///|
test "gateway address translation" {
  let gateway = Gateway::new()
  let rule = GatewayRule::new(1, 2, 3, 0, 100, 20).unwrap()
  ignore(gateway.add_rule(rule))
  let translated = gateway.translate(read_holding(1, 3, 1)).unwrap()
  inspect(translated.unit_id.to_int(), content="2")
  inspect(
    ((translated.pdu.data[0].to_uint16() << 8) |
    translated.pdu.data[1].to_uint16()).to_int(),
    content="103",
  )
  inspect(gateway.translated_count(), content="1")
}

///|
test "file records and device identification" {
  let reference = FileRecordReference::new(1, 0, 2).unwrap()
  let record = FileRecordWrite::new(reference, [11, 22]).unwrap()
  let device = Device::new(1).unwrap()
  ignore(device.file_store().put(record))
  let request = read_file_record(1, [reference]).unwrap()
  let response = device.handle(request).unwrap()
  debug_inspect(
    decode_file_record_response(request, response).unwrap(),
    content="[[11, 22]]",
  )
  let id_request = read_device_identification(1, Basic, 0).unwrap()
  let object = DeviceIdObject::new(0, "moonbit-modbus").unwrap()
  let id_response = encode_device_identification(1, Basic, 1, false, 0, [object]).unwrap()
  let identity = decode_device_identification(id_request, id_response).unwrap()
  inspect(identity.objects.length(), content="1")
}

///|
test "schema and address allocator" {
  let schema = RegisterSchema::new().unwrap()
  let field = RegisterField::new("speed", 0, Unsigned16, writable=true).unwrap()
  ignore(schema.add(field))
  let bank = RegisterBank::new(0, 4, writable=true).unwrap()
  ignore(schema.write("speed", U16(1500), bank))
  match schema.read("speed", bank).unwrap() {
    U16(value) => inspect(value, content="1500")
    _ => fail("wrong field kind")
  }
  let allocator = AddressAllocator::new(32).unwrap()
  let first = allocator.allocate(8).unwrap()
  let second = allocator.allocate(4).unwrap()
  inspect(first.start().to_int(), content="0")
  inspect(second.start().to_int(), content="8")
  ignore(allocator.release(first))
  inspect(allocator.free_capacity(), content="28")
}

///|
test "conformance and preflight" {
  let frame = read_holding(1, 0, 1)
  let suite = ConformanceSuite::new()
  for vector in round_trip_vectors(frame) {
    suite.add(vector)
  }
  for vector in boundary_vectors(frame) {
    suite.add(vector)
  }
  let results = suite.run()
  inspect(conformance_failed(results), content="0")
  let server = Server::new(default_server_config(Rtu)).unwrap()
  ignore(server.add_device(Device::new(1).unwrap()))
  let report = preflight_server(server)
  inspect(report.ok(), content="true")
}

///|
test "metrics and benchmark counters" {
  let metrics = ProtocolMetrics::new().unwrap()
  ignore(metrics.record_request(8))
  ignore(metrics.record_response(8, 3, false))
  inspect(metrics.requests(), content="1")
  inspect(metrics.responses(), content="1")
  let result = benchmark_rtu_round_trip(8).unwrap()
  inspect(result.successful, content="8")
  inspect(result.failed, content="0")
}

///|
test "transport and text helpers" {
  let device = Device::new(1).unwrap()
  let link = VirtualLink::new(Tcp).unwrap()
  let request = read_holding(1, 0, 1)
  let reply = link.round_trip(device, 9, request).unwrap()
  inspect(reply is Reply(_), content="true")
  let text = format_wire_frame(Rtu, 0, request)
  inspect(parse_wire_frame(Rtu, text[4:].to_owned()) is Ok(_), content="true")
  let health = endpoint_health(device, ProtocolMetrics::new().unwrap())
  inspect(endpoint_score(health), content="100")
}

///|
test "telemetry ring and alarm boundaries" {
  inspect(TelemetryRing::new(0) is Err(CapacityExceeded), content="true")
  let ring = TelemetryRing::new(3).unwrap()
  inspect(ring.latest() is Err(Incomplete), content="true")
  ring.record(1)
  ring.record(2)
  ring.record(3)
  ring.record(4)
  debug_inspect(ring.snapshot(), content="[2, 3, 4]")
  inspect(ring.is_full(), content="true")
  inspect(ring.minimum().unwrap(), content="2")
  inspect(ring.maximum().unwrap(), content="4")
  inspect(ring.delta().unwrap(), content="1")
  inspect(Threshold::new(9, 1) is Err(InvalidData), content="true")
  let threshold = Threshold::new(10, 20).unwrap()
  let monitor = AlarmMonitor::new(threshold)
  inspect(monitor.observe(5) is Below, content="true")
  inspect(monitor.observe(15) is Within, content="true")
  inspect(monitor.observe(25) is Above, content="true")
  inspect(monitor.transitions(), content="2")
  monitor.reset()
  inspect(monitor.last_value() is None, content="true")
}

///|
test "topology route and health boundaries" {
  let topology = NetworkTopology::new(max_nodes=4, max_links=4).unwrap()
  ignore(
    topology.add_node(
      TopologyNode::new("gateway", "Gateway", GatewayNode).unwrap(),
    ),
  )
  ignore(
    topology.add_node(
      TopologyNode::new("device", "Device", DeviceNode, unit_id=1).unwrap(),
    ),
  )
  ignore(
    topology.add_link(
      TopologyLink::new("link", "gateway", "device", 5, 100).unwrap(),
    ),
  )
  let route = topology.route("gateway", "device").unwrap()
  inspect(route.reachable(), content="true")
  inspect(route.hops(), content="1")
  inspect(
    topology.add_node(
      TopologyNode::new("device", "Duplicate", DeviceNode).unwrap(),
    )
    is Err(InvalidData),
    content="true",
  )
  ignore(topology.set_node_health("gateway", Healthy))
  ignore(topology.set_node_health("device", Unreachable))
  inspect(topology.unhealthy_nodes().length(), content="1")
}

///|
test "poll group coalescing and budgets" {
  let plan = PollGroupPlan::new().unwrap()
  let first = PollPoint::new(
    "temperature",
    "plc-a",
    1,
    PollHoldingRegisters,
    10,
    2,
    100,
    priority=2,
  ).unwrap()
  let second = PollPoint::new(
    "pressure",
    "plc-a",
    1,
    PollHoldingRegisters,
    12,
    2,
    100,
    priority=1,
  ).unwrap()
  ignore(plan.add_point(first))
  ignore(plan.add_point(second))
  inspect(plan.point_count(), content="2")
  inspect(plan.group_count(), content="1")
  inspect(plan.groups()[0].quantity(), content="4")
  let budget = PollBudget::new(1, 4).unwrap()
  inspect(plan.budgeted(budget).length(), content="1")
  inspect(
    PollPoint::new("bad", "plc-a", 1, PollHoldingRegisters, 65535, 2, 100)
    is Err(InvalidAddress),
    content="true",
  )
}

///|
test "reliability breaker and sliding window" {
  let window = ReliabilityWindow::new(100).unwrap()
  ignore(window.append(ReliabilitySample::new(1, 10, true, "read").unwrap()))
  ignore(
    window.append(
      ReliabilitySample::new(2, 20, false, "read", failure=TimeoutFailure).unwrap(),
    ),
  )
  inspect(window.success_rate(), content="50")
  inspect(window.failure_count(TimeoutFailure), content="1")
  let circuit = CircuitGuard::new("plc-a", 2, 10).unwrap()
  inspect(circuit.allow(0).unwrap(), content="true")
  ignore(circuit.record_failure(1))
  ignore(circuit.record_failure(2))
  inspect(circuit.state() == OpenCircuit, content="true")
  inspect(circuit.allow(5).unwrap(), content="false")
  inspect(circuit.allow(12).unwrap(), content="true")
}

///|
test "quality pipeline edge decisions" {
  let rule = QualityRule::new(
    "range",
    "temperature",
    RangeTest,
    lower=10,
    upper=20,
  ).unwrap()
  let pipeline = QualityPipeline::new().unwrap()
  ignore(pipeline.add_rule(rule))
  inspect(
    pipeline.evaluate("temperature", 15, 1).unwrap() == QualityAccepted,
    content="true",
  )
  inspect(
    pipeline.evaluate("temperature", 25, 2).unwrap() == QualityRejected,
    content="true",
  )
  inspect(pipeline.rejected(), content="1")
  inspect(
    QualityRule::new("invalid", "temperature", RangeTest, lower=20, upper=10)
    is Err(InvalidData),
    content="true",
  )
}

///|
test "protocol guard duplicate and oversize boundaries" {
  let policy = ProtocolGuardPolicy::new(max_frame_bytes=8, max_frames=2).unwrap()
  let admission = ProtocolGuard::new(policy).unwrap()
  let frame = read_holding(1, 0, 1)
  inspect(
    admission.admit("peer-a", frame, 1).unwrap() == AdmitFrame,
    content="true",
  )
  inspect(
    admission.admit("peer-a", frame, 2).unwrap() == DuplicateFrame,
    content="true",
  )
  let other = Frame::new(1, 3, [0, 0, 0, 1, 0, 0, 0])
  inspect(
    admission.admit("peer-a", other, 3).unwrap() == OversizeFrame,
    content="true",
  )
  inspect(admission.peer_stats("peer-a").unwrap().1, content="2")
}

///|
test "deterministic scenario replay" {
  let scenario = scenario_boundary_suite(1, 3).unwrap()
  let runner = ScenarioRunner::new(scenario).unwrap()
  let results = runner.run_all().unwrap()
  inspect(results.length(), content="3")
  inspect(runner.passed(), content="true")
  debug_inspect(runner.outcome_counts(), content="[1, 0, 0, 1, 0, 1]")
}

///|
test "migration apply and rollback" {
  let snapshot = MigrationSnapshot::new(1, 0).unwrap()
  ignore(snapshot.put("host", "localhost"))
  let plan = MigrationPlan::new("upgrade", 1, 2).unwrap()
  let step = MigrationStep::new(
    "add-port",
    AddSetting,
    "port",
    "502",
    0,
    rollback_value="0",
  ).unwrap()
  ignore(plan.add_step(step))
  let upgraded = plan.apply(snapshot).unwrap()
  inspect(upgraded.version(), content="2")
  inspect(upgraded.get("port") == Some("502"), content="true")
  let restored = plan.rollback(upgraded).unwrap()
  inspect(restored.version(), content="1")
  inspect(restored.get("port") == Some("0"), content="true")
}

///|
test "lease ownership and expiry" {
  let manager = LeaseManager::new(default_duration=10).unwrap()
  let lease = manager.acquire("serial-a", "worker-a", 0).unwrap()
  inspect(
    manager.acquire("serial-a", "worker-b", 1) is Err(Busy),
    content="true",
  )
  ignore(manager.renew(lease.id(), "worker-a", 5, duration=20))
  inspect(manager.owned_by("worker-a", 10).unwrap().length(), content="1")
  ignore(manager.release(lease.id(), "worker-a"))
  inspect(manager.active_resources(10).unwrap().length(), content="0")
}

///|
test "transport and contract observability" {
  let metrics = TransportMetricsRegistry::new().unwrap()
  ignore(metrics.record(MetricsTcp, 1, true, 4, 10, 12))
  ignore(metrics.record(MetricsTcp, 2, false, 8, 10, 0))
  inspect(metrics.total_requests(), content="2")
  inspect(metrics.total_failures(), content="1")
  let contracts = standard_frame_contracts()
  let request = read_holding(1, 0, 1)
  let response = Frame::new(1, 3, [2, 0, 1])
  inspect(
    contracts.check(request, response).unwrap() == ContractPass,
    content="true",
  )
  inspect(
    contracts.check(request, Frame::new(2, 3, [2, 0, 1])).unwrap() ==
    ContractUnitMismatch,
    content="true",
  )
}

///|
test "profile admission scaling and overlap boundaries" {
  let point = ProfilePoint::new(
    "temperature",
    "Temperature",
    HoldingRegisters,
    10,
    1,
    Signed16,
    writable=true,
    scale_numerator=2,
    offset=3,
  ).unwrap()
  inspect(point.register_count(), content="1")
  inspect(point.contains_range(10, 1), content="true")
  inspect(point.contains(11), content="false")
  inspect(point.raw_to_engineering(5), content="13")
  inspect(point.engineering_to_raw(13).unwrap(), content="5")
  inspect(
    ProfilePoint::new("empty", "Empty", HoldingRegisters, 0, 0, Signed16)
    is Err(InvalidQuantity),
    content="true",
  )
  inspect(
    ProfilePoint::new(
      "input",
      "Input",
      InputRegisters,
      0,
      1,
      Signed16,
      writable=true,
    )
    is Err(Unsupported),
    content="true",
  )
  let profile = DeviceProfile::new("meter", "M-1", 1).unwrap()
  ignore(profile.add_point(point))
  let overlap = ProfilePoint::new(
    "overlap",
    "Overlap",
    HoldingRegisters,
    10,
    1,
    Signed16,
  ).unwrap()
  inspect(profile.add_point(overlap) is Err(InvalidAddress), content="true")
  inspect(profile.validate() is Ok(_), content="true")
}

///|
test "alarm delayed lifecycle and timestamp ordering" {
  let rule = AlarmRule::new(
    "high-temp",
    "temperature",
    AtOrAbove,
    0,
    100,
    Critical,
    activation_delay=5,
    clear_delay=3,
  ).unwrap()
  let instance = AlarmInstance::new(rule)
  ignore(instance.evaluate(100, 10, 1))
  inspect(instance.state() == Pending, content="true")
  ignore(instance.evaluate(100, 14, 2))
  inspect(instance.state() == Pending, content="true")
  ignore(instance.evaluate(100, 15, 3))
  inspect(instance.state() == Active, content="true")
  ignore(instance.acknowledge("operator"))
  inspect(instance.state() == Acknowledged, content="true")
  ignore(instance.evaluate(90, 16, 4))
  inspect(instance.state() == Clearing, content="true")
  ignore(instance.evaluate(90, 18, 5))
  inspect(instance.state() == Clearing, content="true")
  ignore(instance.evaluate(90, 19, 6))
  inspect(instance.state() == Normal, content="true")
  ignore(instance.evaluate(200, 18, 7))
  inspect(instance.state() == Normal, content="true")
  inspect(instance.acknowledge("operator") is Err(InvalidData), content="true")
}

///|
test "capture ring overflow filtering and corruption" {
  let ring = CaptureRing::new(max_records=2).unwrap()
  let frame = read_holding(1, 0, 1)
  ignore(ring.push_frame(1, Rtu, 0, Received, frame))
  ignore(ring.push_frame(2, Rtu, 0, Transmitted, frame))
  let corrupt = encode_rtu(frame)
  corrupt[corrupt.length() - 1] = corrupt[corrupt.length() - 1] ^ 1
  ignore(ring.push(3, Rtu, 0, Received, corrupt))
  inspect(ring.length(), content="2")
  inspect(ring.lost(), content="1")
  inspect(ring.decoded_count(), content="1")
  inspect(ring.corrupt_count(), content="1")
  inspect(ring.latest().unwrap().id(), content="3")
  let filter = CaptureFilter::new().with_direction(Received)
  inspect(ring.query(filter).length(), content="1")
  inspect(
    CaptureFilter::new().between(5, 4) is Err(InvalidData),
    content="true",
  )
  ring.clear()
  inspect(ring.length(), content="0")
  inspect(ring.lost(), content="0")
}

///|
test "command request validation priority and audit" {
  let command = DeviceCommand::new(
    "write-1",
    "meter-1",
    1,
    WriteRegisterCommand,
    6,
    12,
    1,
    "operator",
    "setpoint",
    0,
  ).unwrap()
  ignore(command.add_argument(CommandArgument::new("value", "4660").unwrap()))
  let request = command.request().unwrap()
  inspect(request.pdu.function.to_int(), content="6")
  inspect(request.pdu.data[2].to_int(), content="18")
  inspect(request.pdu.data[3].to_int(), content="52")
  let missing = DeviceCommand::new(
    "missing",
    "meter-1",
    1,
    WriteRegisterCommand,
    6,
    12,
    1,
    "operator",
    "setpoint",
    0,
  ).unwrap()
  inspect(missing.request() is Err(InvalidData), content="true")
  let center = CommandCenter::new(max_queue=1).unwrap()
  ignore(center.submit(command, 1))
  let dispatched = center.next(2).unwrap()
  inspect(dispatched.state() == Dispatched, content="true")
  let execution = CommandExecution::new(
    "write-1",
    Acknowledged,
    2,
    4,
    response=Frame::new(1, 6, [0, 12, 18, 52]),
  ).unwrap()
  ignore(center.finish(dispatched, execution))
  inspect(center.queue_count(), content="0")
  inspect(center.completed_count(), content="1")
  inspect(center.audit_count(), content="3")
  inspect(center.recent(2).unwrap().length(), content="2")
}

///|
test "event bus retry and dead letter boundaries" {
  let bus = ServiceEventBus::new(
    max_queue=1,
    max_dead_letters=1,
    max_subscriptions=1,
  ).unwrap()
  let subscription = EventSubscription::new(
    "collector",
    source="sensor-a",
    kind=FrameReceivedEvent,
  ).unwrap()
  ignore(bus.subscribe(subscription))
  inspect(
    bus.subscribe(
      EventSubscription::new("collector", source="sensor-a").unwrap(),
    )
    is Err(CapacityExceeded),
    content="true",
  )
  let event = ServiceEvent::new("event-1", FrameReceivedEvent, "sensor-a", 0, [
    1, 2,
  ]).unwrap()
  ignore(bus.publish(event))
  let claimed = bus.claim("collector").unwrap()
  inspect(claimed.attempts(), content="0")
  ignore(bus.ack(claimed, false, dead_letter_after=2))
  inspect(bus.queue_count(), content="1")
  let retried = bus.claim("collector").unwrap()
  ignore(bus.ack(retried, false, dead_letter_after=2))
  inspect(bus.queue_count(), content="0")
  inspect(bus.dead_letter_count(), content="1")
  inspect(bus.claim("missing") is Err(InvalidData), content="true")
}

///|
test "capacity ledger hard limit release and expiry" {
  let ledger = CapacityLedger::new(max_reservations=2).unwrap()
  ignore(
    ledger.add_limit(
      CapacityLimit::new(InFlightRequests, "requests", 2, 3).unwrap(),
    ),
  )
  let first = ledger.reserve(InFlightRequests, 2, 0).unwrap()
  let second = ledger.reserve(InFlightRequests, 1, 1).unwrap()
  inspect(ledger.pressure().length(), content="1")
  inspect(
    ledger.reserve(InFlightRequests, 1, 2) is Err(CapacityExceeded),
    content="true",
  )
  ignore(ledger.release(first.id()))
  inspect(ledger.release(first.id()) is Err(Busy), content="true")
  inspect(ledger.expire(10, 5).unwrap(), content="1")
  inspect(ledger.limit(InFlightRequests).unwrap().used(), content="0")
  inspect(second.released(), content="true")
}

///|
test "device snapshot quality and service lifecycle" {
  let service = DeviceService::new(
    "poller-1",
    "meter-1",
    PollingService,
    "serial://ttyS1",
  ).unwrap()
  ignore(service.start(1))
  inspect(service.state() == ServiceRunning, content="true")
  ignore(service.drain())
  ignore(service.stop(2))
  ignore(service.restart(3))
  inspect(service.restart_count(), content="1")
  let snapshot = DeviceSnapshot::new("meter-1", 10, 1).unwrap()
  let good = SnapshotValue::new("temperature", 20, 10).unwrap()
  let bad = SnapshotValue::new("pressure", 0, 10, quality=Disconnected).unwrap()
  ignore(snapshot.add(good))
  inspect(snapshot.add(good) is Err(InvalidData), content="true")
  inspect(snapshot.finish(3) is Err(Incomplete), content="true")
  ignore(snapshot.add(bad))
  ignore(snapshot.finish(2))
  inspect(snapshot.complete(), content="true")
  inspect(snapshot.good_count(), content="1")
  inspect(snapshot.quality() == Substituted, content="true")
}

///|
test "historian ordering windows and aggregation" {
  let series = TagSeries::new("temperature", max_samples=2).unwrap()
  ignore(series.append(TagSample::new("temperature", 1, 10).unwrap()))
  ignore(
    series.append(
      TagSample::new("temperature", 2, 20, quality=OutOfRange).unwrap(),
    ),
  )
  inspect(
    series.append(TagSample::new("temperature", 0, 5).unwrap())
    is Err(InvalidData),
    content="true",
  )
  inspect(series.average(1, 2).unwrap(), content="10")
  inspect(series.aggregate(1, 2, MaximumValue).unwrap(), content="20")
  ignore(series.append(TagSample::new("temperature", 3, 30).unwrap()))
  inspect(series.length(), content="2")
  inspect(series.dropped(), content="1")
  inspect(series.first().unwrap().timestamp(), content="2")
  inspect(series.between(3, 2) is Err(InvalidData), content="true")
}
