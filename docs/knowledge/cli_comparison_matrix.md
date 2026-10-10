# ADK CLI Comparison Matrix (Python / Dart / JS / Go / Java / Kotlin)

Snapshot date: 2026-10-10  
Compared versions / snapshots:
- `adk-python`: `v2.11.0+` (`15486dbb2`)
- `adk_dart` / `packages/adk`: `2026.10.7+` (`2026-10-10` parity)
- `adk-js` devtools CLI package (`@google/adk-devtools`): `86d1cfef`
- `adk-go`: `987c7bc0`
- `adk-java`: `189d463a`
- `adk-kotlin`: `89c796cd`

Status legend:
- `Y`: supported as CLI command with full option parity
- `Partial`: supported with a different shape (alias/target switch/build-tool goal)
- `N`: not currently supported as CLI command

| Command family | `adk-python` (`adk`) | `adk_dart` (`adk`) | `adk-js` (`adk`) | `adk-go` (`adkgo`) | `adk-java` / `adk-kotlin` | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| CLI entrypoint (`adk`, `--version`) | Y | Y | Y | Y | Partial | Java/Kotlin use Maven/Gradle plugin tasks rather than a unified `adk` binary. |
| `create` (`--model`, `--api_key`, `--project`, `--region`, `--type`) | Y | Y | Y | N | N | `adk_dart` supports `CODE`, `CONFIG`, `BASIC`, and `WORKFLOW` project generation + `.env` / YAML authoring. |
| `run [query]` (`--timeout`, `--in_memory`, `--jsonl`, `--resume`, `--replay`) | Y | Y | Y | N | N | `adk_dart` supports positional `[query]`, `--jsonl`, `--timeout`, `--in_memory`, auto-resume, and exit code `2` on HITL pause. |
| `web` (Trigger routes, OIDC, Avatar, Enterprise/Express mode) | Y | Y | Y | N | Partial | Both `adk-python` and `adk_dart` bundle the latest `adk-web` SPA and support `/dev/apps` & trigger routes. |
| `api_server` (`--with_ui`, Trigger routes, OIDC, A2A) | Y | Y | Y | N | Partial | Full headless API server parity + optional `--with_ui` toggle. |
| `deploy cloud_run` | Y | Y | Y | Y | N | Supports `--with_cloud_run_sandbox`, `--extra_packages`, `--trigger_sources`, OIDC validation, and mutual-exclusivity checks. |
| `deploy docker` | Y | Y | N | N | N | Generates staging bundle and production `Dockerfile` (`toDocker`). |
| `deploy agent_engine` | Y | Y | N | N | N | Supports `--extra_packages`, `--provider_args`, `--env KEY=VALUE`, and `agent_engine_id`. |
| `deploy gke` | Y | Y | N | N | N | Supports `--cluster_name`, `--service_type`, `--worker_pool`, and `--with_cloud_run_sandbox`. |
| `eval` | Y | Y | N | N | N | Supports `--config_file_path`, `--print_detailed_results`, and `--eval_storage_uri`. |
| `eval_set create` / `add_eval_case` / `generate_eval_cases` | Y | Y | N | N | N | Includes synthetic case generation via `generate_eval_cases`. |
| `optimize` | Y | Y | N | N | N | GEPA root agent prompt optimization (`--sampler_config_file_path`, `--optimizer_config_file_path`). |
| `conformance record` / `test` | Y | Y | N | N | N | Supports `replay` and `live` conformance modes plus Markdown report generation. |
| `migrate session` (`--allow-unsafe-unpickling`) | Y | Y | N | N | N | Migrates session databases across SQLite/PostgreSQL/MySQL and legacy pickle schemas. |
| `telemetry` (`enable` / `disable` / `status`) | Y | Y | N | N | N | Manages `~/.adk/config.json` telemetry preferences. |
| `test [folder]` (`--rebuild`, `-- <args>`) | Y | Y | N | N | N | Runs agent test suites with `--rebuild` and test runner argument passthrough. |
| `doctor` / `diag` | N | Y | N | N | N | Dart-specific environment & SDK diagnostic command. |

## Source of Truth (code references)

- `adk-python` CLI command declarations: `../ref/adk-python/src/google/adk/cli/cli_tools_click.py`
- `adk-python` deploy implementation: `../ref/adk-python/src/google/adk/cli/cli_deploy.py`
- `adk_dart` CLI parsing/dispatch: `packages/adk/lib/src/dev/cli.dart`, `packages/adk/lib/src/cli/cli_tools_click.dart`
- `adk_dart` deploy target options: `packages/adk/lib/src/cli/cli_deploy.dart`
- `adk_dart` interactive/single-query runner: `packages/adk/lib/src/adk_cli_runner.dart`
- `adk_dart` web/API server & triggers: `packages/adk/lib/src/dev/web_server.dart`, `packages/adk/lib/src/cli/trigger_routes.dart`
