# moonbit-modbus

`moonbit-modbus` 是一个面向工业设备接入的 MoonBit Modbus 协议栈。它把 PDU、RTU、ASCII 和 TCP MBAP 统一到同一套类型安全 API，并提供设备内存、客户端事务、轮询、网关和虚拟链路等可组合模块，适合 PLC、变频器、仪表、数据采集器和协议测试工具。

## 核心能力

- 协议编解码：Modbus RTU、ASCII、TCP，CRC16、LRC、MBAP 事务标识和异常响应。
- 功能码覆盖：线圈、离散输入、保持寄存器、输入寄存器的读写，以及掩码写、读写组合、诊断、事件计数器、文件记录、设备识别和 FIFO。
- 流式处理：有界增量解析器支持分段输入、多帧输入和坏帧恢复，避免无界缓存。
- 设备与内存：寄存器/线圈 bank、地址空间、schema、文件记录存储、设备状态和异常统计。
- 集成组件：客户端重试与超时、请求规划、轮询计划、批处理、网关映射、服务器池和虚拟传输链路。
- 工程质量：无第三方运行时依赖，支持 native、wasm 和 wasm-gc 目标；公共接口生成 `.mbti` 文件并由 CI 校验。

## 快速开始

需要已安装 MoonBit stable 工具链。仓库根目录执行：

```bash
moon update
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run cmd/main
```

最小 API 示例：

```moonbit nocheck
///|
let request = @moonbit-modbus.read_holding(1, 0, 4)

///|
let rtu_bytes = @moonbit-modbus.encode_rtu(request)

///|
let parsed = @moonbit-modbus.decode_rtu(rtu_bytes)
```

增量解析示例：

```moonbit nocheck
///|
let parser = @moonbit-modbus.IncrementalParser::new(@moonbit-modbus.rtu_mode())

///|
let frames = parser.feed(rtu_bytes)
```

## CLI

仓库包含两个可直接运行的示例程序：

```bash
# 展示请求编码、虚拟设备处理和响应格式化
moon run --target native cmd/main

# 运行 1000 次 CRC、RTU、TCP 和设备读工作负载
moon run --target native cmd/bench
```

`cmd/bench` 输出确定性的迭代次数、成功数、失败数和处理字节数；独立的端到端命令耗时记录在 [BENCHMARK.md](BENCHMARK.md)。

## 架构

代码按协议边界拆分为几个层次：

1. `types.mbt`、`validation.mbt` 和 `limits.mbt` 定义公共类型、功能码、异常码和边界规则。
2. `codec.mbt`、`checksum.mbt`、`parser.mbt` 和 `frame_text.mbt` 负责 PDU/ADU 编解码、校验和流式解析。
3. `functions.mbt`、`responses.mbt`、`coils.mbt`、`register_codec.mbt` 和 `file_records.mbt` 提供功能码与数据表示。
4. `banks.mbt`、`device.mbt`、`register_schema.mbt` 和 `address_space.mbt` 组成可测试的设备内存层。
5. `client.mbt`、`transport.mbt`、`polling.mbt`、`gateway.mbt`、`server_pool.mbt` 和 `simulation.mbt` 提供系统集成能力。
6. `conformance.mbt`、`preflight.mbt`、`quality.mbt`、`metrics.mbt` 和 `benchmark_core.mbt` 提供一致性检查、运行指标和可复现基准。

核心层只依赖 MoonBit 标准能力；真实串口和 TCP socket 可在上层适配，而不改变协议模型和测试夹具。

## 基准

基准使用 native 目标和固定的 1000 次迭代，覆盖 CRC16、RTU 编解码往返、TCP 编解码往返和设备读路径。结果分为确定性工作量统计与主机端到端耗时两部分，避免把不同机器的时钟结果伪装成协议吞吐率。复现实验方法和原始测量值见 [BENCHMARK.md](BENCHMARK.md)。

## 测试

测试覆盖正常路径和边界路径，包括：

- 地址、单位号、数量、PDU/ADU 长度、字节计数和广播请求边界；
- CRC/LRC、ASCII/TCP/RTU 错帧、分段输入、多帧输入和截断输入；
- 线圈 bit packing、寄存器字节序、32/64 位数值、游标越界和写入器容量；
- 设备读写、异常响应、busy 状态、文件记录、设备识别、客户端事务和网关映射；
- schema、轮询、批处理、预检、指标、虚拟传输和文本帧工具。

本地质量门槛：

```bash
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target all --deny-warn
```

## CI

`.github/workflows/check.yml` 在 Ubuntu、macOS 和 Windows 上安装 MoonBit stable，执行 `moon update`、格式检查、全目标检查、构建、测试、CLI smoke test 和 `.mbti` 清洁工作树校验。`.github/workflows/publish.yml` 仅支持手动触发，用于在配置发布凭据后执行 Mooncakes 发布流程。

## 许可证

本项目采用 [Apache-2.0](LICENSE) 许可证。协议实现依据公开的 Modbus 应用协议与串行链路规范重新实现，源码和测试夹具均保留在本仓库中。
