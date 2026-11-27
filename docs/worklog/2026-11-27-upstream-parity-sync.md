# 2026-11-27 Upstream Parity Sync (`2026.11.27`)

## Upstream Status
- `adk-python`: `03725e8c67ca27b2c07569797a0c18e867e0b217` (`v2.15.1`, 0 new upstream commits)
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, 0 new upstream commits; `main-PJ4DBNMP.js` already synced)

## Included 1-Month Parity Fixes (Committed After `v2026.11.26`)
1. `babacf7e` — `fix(plugins,features,telemetry): align ReflectAndRetryToolPlugin guidance replacement, feature registry defaults, and Agent Engine trace propagation` (`77/77` + `3/3` tests passed)
2. `d7330041` — `fix(integrations,sessions): align OpenAI Decisions wire schema, VMaaS >1MiB reads, Redis transactions/JSON-safe state, and Teams sender/error parity` (`156/156` tests passed)
3. `1808a2ac` — `fix(core,models,flows,tools): align Anthropic thinking tool choice, CallbackType scoping, YAML denylist, tool display names, bash 0 limits, and NodeTool traversal` (`185/185` tests passed)
4. `cd8fdfd9` — `fix(cli,server): wire --python_version and startup import validation, Agent Engine trace propagation, 404 reserved apps, NodeTool app-info, and trigger error sanitization` (`135/135` tests passed)

## Release
- Version: `2026.11.27` (`adkVersion = '2.15.1'`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
