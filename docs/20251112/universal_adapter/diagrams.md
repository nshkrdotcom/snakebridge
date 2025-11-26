# Instrumented Adapter Architecture (Diagrams)

## 1. Layered Stack
```
+---------------------------------------------------------------+
|                    Developer Experience Layer                 |
|  - Mix tasks (`snakebridge.inspect`, `snakebridge.profile`)    |
|  - VSCode/LSP hints                                           |
|  - Auto-generated docs & dashboards                           |
+---------------------------▲-----------------------------------+
                            │ telemetry & diagnostics API
+---------------------------│-----------------------------------+
|     SnakeBridge Capability Engine (Profiles + Schema v2)      |
|  - Config parser + profile library                            |
|  - Runtime refinement (instrumentation feedback loop)         |
|  - Hook modules / customization slots                         |
+---------------------------▲-----------------------------------+
                            │ normalized execution envelopes
+---------------------------│-----------------------------------+
|          Snakepit Execution Fabric (pool, streams)            |
|  - Worker lifecycle, session affinity                         |
|  - gRPC streaming + heartbeat telemetry                       |
|  - Python bridge adapters (process & thread profiles)         |
+---------------------------▲-----------------------------------+
                            │ gRPC/tool invocations
+---------------------------│-----------------------------------+
|               Python Runtime + Library Adapters               |
|  - Auto-generated scaffolding (SnakeBridge Runtime)           |
|  - Instrumentation hooks (async/stream metadata)              |
|  - Target library (LangGraph, AutoGen, etc.)                  |
+---------------------------------------------------------------+
```

## 2. Telemetry Feedback Loop
```
            ┌────────────────────────────────────────┐
            │ SnakeBridge Profile Decl (e.g. :stream)│
            └────────────────────────────────────────┘
                          │ configure
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Runtime Execution (Snakepit worker + Python adapter)        │
│  • emits span/metric events with execution_mode hints       │
└───────────────┬─────────────────────────────────────────────┘
                │ telemetry stream (events, metrics, logs)
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Telemetry Analyzer                                          │
│  • correlates run_id/session_id                             │
│  • compares observed behavior vs. declared profile          │
│  • flags mismatches (e.g., generator detected)              │
└───────────────┬─────────────────────────────────────────────┘
                │ diagnostics report / suggested actions
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Developer UX                                                │
│  • `mix snakebridge.inspect Foo.Bar`                        │
│  • LSP warnings / doc annotations                           │
│  • Auto-patch suggestions for config                        │
└─────────────────────────────────────────────────────────────┘
```

## 3. Streaming Adapter Decision Tree
```
Start
 │
 │-- Python result is awaitable? ──► wrap via AwaitableAdapter (resolve future)
 │
 │-- Python returns generator? ──► wrap via GeneratorAdapter (chunk per yield)
 │
 │-- Python registers callback? ──► wrap via CallbackAdapter (subscribe + proxy)
 │
 │-- Python spawns background task? ──► wrap via TaskChannelAdapter (status + final)
 │
 └─► Default synchronous adapter
```
