# Benchmark

This document records a reproducible local run of `cmd/bench`. The benchmark is intentionally small and deterministic: it reports protocol work completed by the library, while the wall-clock section reports the full CLI invocation separately.

## Command

```text
moon run --target native cmd/bench
```

The command runs four workloads with 1,000 iterations each:

| Workload | Iterations | Successful | Failed | Bytes |
| --- | ---: | ---: | ---: | ---: |
| CRC16 | 1,000 | 1,000 | 0 | 6,000 |
| RTU encode/decode round trip | 1,000 | 1,000 | 0 | 8,000 |
| TCP encode/decode round trip | 1,000 | 1,000 | 0 | 12,000 |
| Device read | 1,000 | 1,000 | 0 | 3,000 |
| **Total** | **4,000** | **4,000** | **0** | **29,000** |

## Host measurement

Measured on 2026-08-19 with five consecutive invocations of the same command. The measurement includes Moon's CLI startup and native program launch, so it is an end-to-end regression signal rather than an isolated function throughput claim.

```text
MoonBit: moon 0.1.20260807 / moonc v0.10.7
CPU: AMD Ryzen 7 5800H with Radeon Graphics
OS: Microsoft Windows 11 家庭版
runs_ms: 328.77, 237.33, 242.95, 238.43, 236.24
min_ms: 236.24
median_ms: 238.43
```

To reproduce the timing on another host, run the command five times with a stopwatch and record the toolchain and CPU alongside the result. The deterministic counters should remain unchanged across hosts.
