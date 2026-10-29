# Changelog

## 2026.10.29

- Bumped package version to `2026.10.29` and dependency `adk_dart: ^2026.10.29`.
- **CLI & Dev Web Server Security & Reliability (`cli.dart`, `web_server.dart`, `adk-python` `27dda3e11`, `ff66b1f17`, `b7ac5ef75`, `3b227d6ec`, `e2e9336a7`)**:
  - Wrapped `FileSystemException` when reading `--avatar_config` into `CliUsageError` (`27dda3e11`).
  - Added `file://` URI support and `ADK_EVAL_STORAGE_URI` environment variable fallback for evaluation storage (`ff66b1f17`).
  - Protected internal special agents (`__*`) and `/dev/*` routes from foreign browser origins when wildcard or regex `allow_origins` are configured (`b7ac5ef75`).
  - Closed `/run_live` WebSockets cleanly with `1007` (`invalidFramePayloadData`) on malformed request frames and `1011` (`internalServerError`) on unhandled runner failures while aborting the active live session (`3b227d6ec`).

## 2026.10.24

- Bumped package version to `2026.10.24` and dependency `adk_dart: ^2026.10.24`.
- Synced CLI runtime and `adk-web` server integration with `adk_dart` `2026.10.24` (`adk-python` `v2.13.0` parity: `MongoDbMemoryService`, BigQuery workflow node observations, `AgentTool` `temp:` state propagation, failed A2A task error events, and `LiteLlm` quoted tool call filtering).

## 2026.10.23

- Bumped package version to `2026.10.23` and dependency `adk_dart: ^2026.10.23`.
- **Multi-Run CLI Evaluation & Dev Web Server (`cli_eval.dart`, `cli.dart`, `web_server.dart`)**:
  - Added `--num_runs` option to `adk eval` and formatted multi-run evaluation summaries and per-case metric aggregation breakdowns (`MEAN_OVER_INVOCATIONS`, `MEAN_OF_RUNS`, `MIN_OVER_RUNS`, `PASS_RATE`).
  - Added `cache_creation_token_count` serialization in `/run` and `/run_sse` event payloads.
  - Aborted active `/run` and `/run_sse` agent runs immediately when the HTTP client disconnects (`response.done` error listener).
- Upgraded direct and dev dependencies (`crypto: ^3.0.7`, `sqlite3: ^3.7.1`, `yaml: ^3.1.4`, `http: ^1.6.0`, `meta: ^1.19.0`, `lints: ^6.1.0`, `test: ^1.33.0`).

## 2026.10.22

- Bumped package version to `2026.10.22` and dependency `adk_dart: ^2026.10.22`.
- **Dev Web Server & CLI Deployment (`web_server.dart`, `cli_deploy.dart`, `conformance_replay_plugin.dart`)**:
  - Exposed `POST /apps/{app_name}/users/{user_id}/sessions/{session_id}/rewind` and cancelled any active `/run`, `/run_sse`, or `/run_live` session runs before rewinding.
  - Restricted `allowSpecialAgents` to require both `enableWebUi` and a loopback `serverHost`.
  - Added `Dockerfile` and `deployment.yaml` to reserved extra package names in `adk deploy`.
  - Executed `exit_loop` directly during conformance replay instead of looking up a recorded tool response.

## 2026.10.15

- Bumped package version to `2026.10.15` and dependency `adk_dart: ^2026.10.15`.

- **Web Server & Graph Serialization (`web_server.dart`, `agent_graph.dart`)**:
  - Added screencast WebSocket endpoint (`/apps/{appName}/screencast`) for live computer use and browser screencast streaming.
  - Serialized nested workflow nodes, parallel workers, and input/output schemas in graph serialization (`agent_graph.dart`).
  - Added wire mappings for `A2aTaskState.rejected` and `unknown`.
  - Returned HTTP 404 for missing evaluation results or sessions.

## 2026.10.10

- **Full 1:1 `adk-python` CLI Option & Subcommand Parity**:
  - **`adk create`**: Added `--model` / `-m`, `--api_key` / `-k`, `--project` / `-p`, `--region` / `-r`, and `--type` (`CODE` | `CONFIG` | `BASIC` | `WORKFLOW`) with `root_agent.yaml`, `sub_agent_1.yaml`, `sub_agent_2.yaml`, and `.env` generation.
  - **`adk run [query]`**: Added optional positional `[query]`, `--timeout` (`30`, `10s`, `5m`, `1h`), `--in_memory`, `--jsonl` (structured JSONL event output), `--default_llm_model`, `--save_session` / `--no-save_session`, `-v` / `--verbose`, `--log_level` / `--verbosity`, auto-resume on trailing user event, and exit code `2` on HITL pause.
  - **`adk web` & `adk api_server`**: Added `--avatar_config`, `--max_llm_calls`, `--default_llm_model`, `--trigger_sources` (`pubsub`, `eventarc`, `webhook`), `--trigger_oidc_audience`, `--trigger_oidc_service_accounts`, `--with_ui` / `--no-with_ui`, `--gemini_enterprise_app_name`, `--express_mode`, `/dev/apps/...` routes, and `/run_live` WebSocket message/keepalive/concurrency bounds.
  - **`adk deploy`**: Added `adk deploy docker` (`toDocker`), `--cluster_name`, `--service_type`, `--worker_pool`, `--with_cloud_run_sandbox`, `--extra_packages`, `--provider_args`, `--env KEY=VALUE`, `--trigger_sources`, `--trigger_oidc_audience`, `--trigger_oidc_service_accounts`, `--adk_version`, mutual-exclusivity validation (`--use_local_storage` vs service URIs), and `--with_ui` production warning.
  - **`adk eval_set` / `adk migrate session` / `adk test`**: Added `adk eval_set generate_eval_cases`, `adk migrate session --allow-unsafe-unpickling`, `adk test [folder] --rebuild -- <args>`, `adk --version`, and `adk doctor` / `adk diag`.
- Synced `adk-web` browser bundle (`main-NZEGJ4FM.js`) and completed 100% API doc comments and examples.

## 2026.10.7

- Bumped package version to `2026.10.7` and dependency `adk_dart: ^2026.10.7`.
- Synced `adk-web` browser bundle (`main-FSTPJ7PI.js`) and `built_in_agents` (`adk_agent_builder_assistant` with `_adk_symbols.py`) with upstream v2.11.0+.

## 2026.9.11

- Bumped package version to `2026.9.11` and dependency `adk_dart: ^2026.9.11`.
- Updated CLI runtime to support upstream v2.9.0 parity features.

## 2026.9.7

- Bumped package version to `2026.9.7` and dependency `adk_dart: ^2026.9.7`.
- Synced fresh `adk-web` Angular bundle into `lib/src/cli/browser/` featuring Live video response streaming and updated trace inspector.
- Updated CLI tooling to support fallback models and latest workflow engine orchestration.

## 2026.8.17+2

- Updated README installation guides with latest `pubspec.yaml` dependency specifications.

## 2026.8.17+1

- Physically migrated all CLI submodules, Dev WebServer, and Angular Web UI static bundle into `packages/adk` as a standalone official CLI package.
- 100% parity with `adk-python` click commands including `adk telemetry`, `adk test`, and `adk doctor`.
- Upgraded default model in starter templates to `gemini-3.7-flash`.
- Updated dependency alignment to `adk_dart: ^2026.8.17`.

## 2026.8.17

- Bumped package version to `2026.8.17` and dependency `adk_dart: ^2026.8.17`.
- Synced facade release with `adk_dart` `2026.8.17` rollout.

## 2026.7.30

- Bumped package version to `2026.7.30` and dependency `adk_dart: ^2026.7.30`.

## 2026.7.24

- Bumped package version to `2026.7.24`.
- Updated dependency alignment to `adk_dart: ^2026.7.24`.
- Synced facade release with `adk_dart` `2026.7.24` rollout.

## 2026.7.11

- Bumped package version to `2026.7.11`.
- Updated dependency alignment to `adk_dart: ^2026.7.11`.
- Synced facade release with `adk_dart` `2026.7.11`, including ADK 2.0
  Managed Agent support, Interactions API integration, and
  `RemoteMcpServer` for server-side tool execution.

## 2026.6.6

- Bumped package version to `2026.6.6`.
- Updated dependency alignment to `adk_dart: ^2026.6.6`.
- Synced facade release with `adk_dart` `2026.6.6`, including the `2.2.0` ADK baseline update, workflow parity expansion, event conversion fixes, telemetry/plugin updates, and latest runtime hardening.

## 2026.4.17

- Bumped package version to `2026.4.17`.
- Updated dependency alignment to `adk_dart: ^2026.4.17`.
- Synced facade release with `adk_dart` `2026.4.17`, including the `1.31.0` ADK baseline update and latest live/runtime parity fixes.

## 2026.3.21

- Bumped package version to `2026.3.21`.
- Updated dependency alignment to `adk_dart: ^2026.3.21`.
- Synced facade release with the latest `adk_dart` parity work, including session/storage parity, `SpannerAdminToolset`, `environment_simulation`, evaluation metric expansion, Slack/Agent Registry/IAM integration surfaces, and the latest A2A/Discovery Engine/skills compatibility updates.

## 2026.3.13

- Bumped package version to `2026.3.13`.
- Updated dependency alignment to `adk_dart: ^2026.3.13`.
- Synced facade release with the latest `adk_dart` parity work, including skills/API Registry/A2A runtime alignment, Anthropic and BigQuery parity updates, and CLI conformance/MCP schema improvements.

## 2026.3.6

- Bumped package version to `2026.3.6`.
- Updated dependency alignment to `adk_dart: ^2026.3.6`.
- Synced facade release with `adk_dart` `2026.3.6`, including the latest local session-path fix and March Python parity updates.

## 2026.3.2+4

- Bumped package version to `2026.3.2+4`.
- Synced facade release with `adk_dart` `2026.3.2+4`, including positional deploy target parity updates.

## 2026.3.2+3

- Bumped package version to `2026.3.2+3`.
- Synced facade release with `adk_dart` `2026.3.2+3`, including conformance live-mode execution support.

## 2026.3.2+2

- Bumped package version to `2026.3.2+2`.
- Synced facade release with `adk_dart` `2026.3.2+2`, including web/api_server project loading parity and `/run` auto session-create request behavior.

## 2026.3.2+1

- Bumped package version to `2026.3.2+1`.
- Synced facade release with the `adk_dart` `2026.3.2+1` build and CLI parity updates.

## 2026.3.2

- Bumped package version to `2026.3.2`.
- Updated dependency to `adk_dart: 2026.3.2`.

## 2026.3.1

- Bumped package version to `2026.3.1`.
- Updated dependency to `adk_dart: 2026.3.1`.
- Synced facade release with the latest `adk_dart` runtime and telemetry parity updates.

## 2026.2.28

- Switched package versioning scheme to date-based `YYYY.M.D`.
- Updated dependency constraint to `adk_dart: ^2026.2.28`.
- Synced facade package release with latest `adk_dart` web/MCP parity work.

## 0.1.2

- Added package topics metadata on pub.dev to improve discoverability.
- Updated dependency constraint to `adk_dart: ^0.1.2`.

## 0.1.1

- Bumped `adk` package version to align with `adk_dart` `0.1.1`.
- Re-export surface now includes the latest parity additions delivered in `adk_dart`.

## 0.1.0

- Initial package release for `adk_dart`.
