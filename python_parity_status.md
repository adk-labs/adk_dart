# ADK Dart Python Parity Status

Last updated: 2026-02-22
Reference: `ref/adk-python/src/google/adk`

## Core Runtime

- [x] agents
- [x] events
- [x] sessions (in-memory)
- [x] runner (in-memory)
- [x] base tools / function tools
- [x] base plugins
- [x] artifacts (in-memory)
- [x] dev CLI (`create`, `run`, `web`)

## Newly Added Foundation (this iteration)

- [x] memory base + in-memory service
- [x] auth credential models
- [x] credential service base + in-memory + session-state
- [x] telemetry base + in-memory trace service
- [x] evaluation base + local evaluator skeleton
- [x] code executors base + unsafe local executor
- [x] dependencies container skeleton
- [x] platform runtime environment skeleton
- [x] feature flags skeleton
- [x] planner skeleton (rule-based)
- [x] optimization skeleton
- [x] skills registry skeleton
- [x] A2A in-memory router skeleton

## Remaining for Full Python Parity

- [ ] full auth flow parity (OAuth exchange/refresh registries, preprocessors)
- [ ] code executors parity
- [ ] planners/optimization/features parity
- [ ] telemetry parity with OTEL semconv mapping
- [ ] full evaluation suite parity (metric registry, simulation, managers)
- [ ] A2A protocol parity
- [ ] skills framework parity
- [ ] platform/dependencies/utils parity modules
- [ ] full tool ecosystem parity (OpenAPI, MCP advanced, integrations, retrieval, etc.)
- [ ] production-grade web/dev server parity with Python CLI behavior

## Notes

- This file tracks implementation progress in `adk_dart`.
- “Full parity” requires multiple iterations; each completed slice must include tests.
