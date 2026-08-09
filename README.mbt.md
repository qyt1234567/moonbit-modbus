# moonbit-modbus

一个面向工业设备接入的 MoonBit Modbus 协议核心库。它把 RTU、ASCII 和 TCP 的传输封装统一到同一套 PDU API，适合作为 PLC、变频器、仪表、网关和测试工具的协议基础。

## 当前能力

- Modbus PDU、RTU ADU、ASCII 帧和 TCP MBAP 头的编码与解码。
- CRC16（低字节在前）和 ASCII LRC 校验。
- 有界增量解析器，适合串口或 Socket 的分段读取，并避免输入无限增长。
- 读保持寄存器、写单寄存器请求构造，以及寄存器到有符号整数和 32 位浮点原始字的映射。
- 纯 MoonBit 核心层，不依赖具体操作系统；串口、TCP Socket、设备轮询和网关调度由后续适配包提供。

## 快速开始

```bash
moon test --target native
moon run cmd/main
```

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
let frames = parser.feed(partial_bytes)
```

## 设计边界与路线

第一阶段优先保证协议字节级正确性和可测试性。下一阶段会增加功能码 01/02/04/05/0F/10、异常响应校验、设备寄存器 schema、串口/TCP transport trait、虚拟设备、轮询器和网关桥接。OPC UA 适配属于后续集成层，不会混入核心包。

## 与现有生态的差异

在 2026-08-10 以 `modbus`、`industrial protocol`、`RTU`、`MBAP` 等关键词检查 Mooncakes 后，未发现成熟的 Modbus MoonBit 包。现有相关结果主要是通用 buffer、socket 或其他协议/工具库；本项目的独立贡献是提供工业 Modbus 的统一 PDU/ADU 核心和跨传输增量解析边界，而不是重复通用字节容器。

## 来源与许可证

本仓库的 MoonBit 源码、测试和示例均为本项目独立编写，没有复制第三方实现或测试夹具。协议字段和校验算法依据公开的 Modbus Application Protocol Specification V1.1b3 与 Serial Line Protocol and Implementation Guide 进行重新实现；这些规范是协议参考资料，不是代码来源。项目使用 Apache-2.0，详见根目录 [LICENSE](LICENSE)。

## 贡献与质量门槛

提交前运行：

```bash
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon check --target all --deny-warn
moon test --target all --deny-warn
moon info
```

欢迎通过 issue 提交设备互操作样例、功能码需求和性能数据；请不要提交真实工业现场的敏感地址、凭据或商业报文。
