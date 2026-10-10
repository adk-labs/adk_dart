# 2026-10-10 Full 1:1 `adk-python` CLI Options Parity & Analyzer Zero-Issue Cleanup Worklog

## Overview
This worklog documents the two work units completed on `2026-10-10`:
1. **Work Unit 1 (`adk_dart` Core)**: Session migration `--allow-unsafe-unpickling` support and full resolution of all `dart analyze` lints across `lib/src/` and `test/`.
2. **Work Unit 2 (`packages/adk` CLI Toolchain)**: Complete 1:1 command, subcommand, flag, and behavioral parity with `adk-python`'s Click CLI (`cli_tools_click.py`, `cli.py`, `cli_create.py`, `cli_deploy.py`, `cli_eval.py`, `fast_api.py`).

---

## 1. Work Unit 1: Core Session Migration & Analyzer Lint Cleanup (`adk_dart`)
- **Session Migration (`lib/src/sessions/migration/migration_runner.dart`)**:
  - Added `allowUnsafeUnpickling` parameter to `migrateSessionDatabase` and forwarded it to `migrateFromSqlitePickle` to match `adk-python`'s `adk migrate session --allow-unsafe-unpickling`.
- **Zero Analyzer Issues Across Core SDK**:
  - Resolved doc-comment reference lints (`comment_references`) in `lib/src/a2a/protocol.dart`, `lib/src/skills/prompt.dart`, and `lib/src/workflow/workflow.dart`.
  - Fixed `unnecessary_null_comparison` in `lib/src/tools/computer_use/computer_use_toolset.dart` and `unnecessary_cast` in `test/computer_use_parity_test.dart`.
  - Fixed `prefer_initializing_formals` in `lib/src/tools/enterprise_search_tool.dart`, `lib/src/tools/google_maps_grounding_tool.dart`, and `lib/src/tools/google_search_tool.dart`.

---

## 2. Work Unit 2: Full 1:1 `adk-python` CLI Option & Subcommand Parity (`packages/adk`)

### 2.1 `adk create` (`cli_create.dart`, `project.dart`, `cli.dart`)
- Added `--model` / `-m`, `--api_key` / `-k`, `--project` / `-p`, `--region` / `-r`, and `--type` (`CODE` | `CONFIG` | `BASIC` | `WORKFLOW`, case-insensitive).
- Generates `root_agent.yaml` (and `sub_agent_1.yaml`, `sub_agent_2.yaml` for `WORKFLOW`) alongside `agent.dart`, `adk.json`, and `.env` (`GOOGLE_GENAI_USE_VERTEXAI=0/1`, `GOOGLE_API_KEY`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`).

### 2.2 `adk run` (`cli.dart`, `adk_cli_runner.dart`)
- Added optional positional `[query]` (`adk run <agent> [query]`) for single-query execution without interactive prompt.
- Added `--timeout` (`30`, `10s`, `5m`, `1h`) with `TimeoutException` exit handling.
- Added `--in_memory` (forces in-memory session/artifact/memory services and disables local storage), `--jsonl` (emits structured JSONL lines matching `adk-python`'s `_print_event` schema: `timestamp`, `author`, `text`, `tool_calls`, `tool_results`, `usage`), `--default_llm_model`, `--save_session` / `--no-save_session`, `-v` / `--verbose`, and `--log_level` / `--verbosity`.
- Implemented auto-resume when a `--resume` session ends with a trailing user event, and returns exit code `2` when an invocation pauses for a Human-in-the-Loop (HITL) input or confirmation request.

### 2.3 `adk web` & `adk api_server` (`cli.dart`, `web_server.dart`, `adk_web_server.dart`, `fast_api.dart`)
- Added `--avatar_config`, `--max_llm_calls`, `--default_llm_model`, `--trigger_sources`, `--trigger_oidc_audience`, `--trigger_oidc_service_accounts`, `--with_ui` / `--no-with_ui`, `--gemini_enterprise_app_name`, and `--express_mode`.
- Enforced security validation requiring `--trigger_oidc_audience` and `--trigger_oidc_service_accounts` when `--trigger_sources` is enabled on non-loopback hosts, and requiring `--gemini_enterprise_app_name` when `--express_mode` is enabled.

### 2.4 `adk deploy` (`cli_deploy.dart`, `cli.dart`)
- Added `adk deploy docker` (`DeployTarget.docker`, `toDocker`) generating a staging bundle and production `Dockerfile` (`python:3.11-slim`, non-root `myuser`, `adk web`/`adk api_server` CMD).
- Added all `adk-python` deploy flags across `cloud_run`, `docker`, `agent_engine`, and `gke`: `--cluster_name`, `--service_type`, `--worker_pool`, `--with_cloud_run_sandbox`, `--extra_packages`, `--provider_args`, `--env` (`KEY=VALUE`), `--trigger_sources`, `--trigger_oidc_audience`, `--trigger_oidc_service_accounts`, `--adk_version`, `--trace_to_cloud`, `--otel_to_cloud`, `--a2a`, `--reload_agents`, and `--use_local_storage` / `--no-use_local_storage`.
- Added mutual-exclusivity validation between `--use_local_storage` and explicit `--session_service_uri` / `--artifact_service_uri` / `--memory_service_uri`, plus a production warning when `--with_ui` is enabled.

### 2.5 `adk eval_set`, `adk migrate session`, `adk test`, `adk --version`, `adk doctor`
- **`adk eval_set generate_eval_cases`**: Generates synthetic evaluation cases (`--user_simulation_config_file`, `--model_name`, `--num_eval_cases`, `--num_turns`) and persists them into the target eval set.
- **`adk migrate session`**: Added `--allow-unsafe-unpickling`.
- **`adk test`**: Added `--rebuild` and passthrough arguments (`-- <args...>`).
- **`adk --version` / `-V` / `-v` / `version`** and **`adk doctor` / `adk diag`**: Exposed top-level version output and environment diagnostics.

---

## 3. Verification
- `dart analyze` in `/Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart`: **No issues found!**
- `dart analyze` in `/Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/adk`: **No issues found!**
- `dart test` in `packages/adk`: **173/173 tests passing (100%)**.
- `dart test test/computer_use_parity_test.dart`: **All tests passing**.
