# 2026-11-19 Upstream Parity Sync (`2026.11.19`)

## Upstream Ranges Synced
- **`adk-python`**: `c6586f19ab8a2bb8b53e70041633b10858d9902e` -> `fb08c784242c9afc3d8645508d8c5c08c9836eb9` (51 commits)
- **`adk-web`**: `969cee92b7e249f4b66c3de1f2d354ab012fc0ce` -> `4b7d11542b2a5540213d0578d733fae86505c024` (5 commits, tag `v1.0.8`)

## Task-Unit Commits
1. `2535b902` — Core, Sessions (`BufferedSessionService`, `SessionWriteBuffer`, `appendEvents`, `SessionPersistenceError`), Workflow checkpoint coalescing & resume schema guard, `RemoteA2aAgent` streaming persistence, `McpInstructionProvider` isolation, `MultimodalToolResultsPlugin` session mode, `getAgentsDict` non-LLM roots, unified `isGoogleApisUrl`, Cloud Run/K8s runtime labels, Gemini 4+ helpers.
2. `ad9eabce` — Models, Context Caching & Live (`BaseLlmConnection.sendContextUpdate`, Gemini `v1beta` default, caller-supplied live tracking headers, context cache refusal & initial `cachedContent` seed, Interactions content lists, `LiteLlm` Gemini 4+, feature registry updates).
3. `6ed36e4f` — Integrations, Environments, Skills, Tools, Evaluation & Optimization (`CheckGroundingClient`, Fsspec per-backend adapters & S3 metadata, BigQuery `searchScope`, `EnvironmentScope`, `SkillToolset` lazy `.adk_skill_hash` refresh, `ModelConsultTool` SDK thinking levels, Gemini 4+ `thinking_level`, `CrossRunCriterionSummary`).
4. `c1d65289` — `packages/adk` CLI, Dev Server, Deployers & `adk-web` `v1.0.8` bundle sync, removal of Visual Agent Builder endpoints and built-in `__` agents, local-client guard on `POST /config/telemetry`, redacted `/run` logging, `adk eval` cross-run criterion means, and deployer/Dockerfile fixes.
