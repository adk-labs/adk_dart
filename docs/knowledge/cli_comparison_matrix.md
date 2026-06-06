# ADK CLI Comparison Matrix (Python / Dart / JS / Go / Java)

Snapshot date: 2026-03-02  
Compared versions / snapshots:
- `adk-python`: `1.26.0`
- `adk_dart`: `2026.3.2`
- `adk-js` devtools CLI package (`@google/adk-devtools`): `0.4.0`
- `adk-go`: upstream snapshot `229dc75a38453cd74f18f73fcc1db818dd3e8111`
- `adk-java`: upstream snapshot `e3ea378051e5c4e5e5031657467145779e42db55`

Status legend:
- `Y`: supported as CLI command
- `Partial`: supported with a different shape (alias/target switch/build-tool goal)
- `N`: not currently supported as CLI command

| Command family | `adk-python` (`adk`) | `adk_dart` (`adk`) | `adk-js` (`adk`) | `adk-go` (`adkgo`) | `adk-java` (Maven plugin) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| CLI entrypoint | Y | Y | Y | Y | Partial | Java uses Maven goal style (`mvn google-adk:web`) rather than a unified `adk` binary. |
| `create` | Y | Y | Y | N | N | Go/Java snapshots do not expose `create` on their primary CLI surfaces. |
| `run` | Y | Y | Y | N | N | Go has launcher packages but no `adkgo run` command in current CLI. |
| `web` | Y | Y | Y | N | Partial | Java supports `web` via Maven plugin goal; Go has web launcher package, not `adkgo web`. |
| `api_server` | Y | Partial | Y | N | Partial | `adk_dart` is `web` alias with UI off; Java web server exposes APIs via plugin-run server. |
| `deploy cloud_run` | Y | Y | Y | Y | N | `adk_dart` supports both `adk deploy cloud_run` and `adk deploy --target cloud_run`; Go uses `adkgo deploy cloudrun`. |
| `deploy agent_engine` | Y | Y | N | N | N | `adk_dart` supports both positional target (`adk deploy agent_engine`) and `--target` form. |
| `deploy gke` | Y | Y | N | N | N | `adk_dart` supports both positional target (`adk deploy gke`) and `--target` form. |
| `eval` | Y | Partial | N | N | N | `adk_dart` now exposes `adk eval`; supports eval-set id/file execution and summary output, but still differs from Python's full config/metric surface. |
| `eval_set create` | Y | Partial | N | N | N | `adk_dart` now exposes `adk eval_set create` with local/GCS manager wiring. |
| `eval_set add_eval_case` | Y | Partial | N | N | N | `adk_dart` now exposes `adk eval_set add_eval_case` (JSON scenarios/session input). |
| `conformance record` | Y | Partial | N | N | N | `adk_dart` now exposes `adk conformance record`, currently JSON-file workflow (not Python's YAML pipeline parity yet). |
| `conformance test` | Y | Y | N | N | N | `adk_dart` now exposes `adk conformance test` replay/live modes + optional markdown report generation. |
| `migrate session` | Y | Y | N | N | N | `adk_dart` now exposes `adk migrate session --source_db_url --dest_db_url`. |

## Source of Truth (code references)

- `adk-python` CLI command declarations: `../ref/adk-python/src/google/adk/cli/cli_tools_click.py`
- `adk-python` package version: `../ref/adk-python/src/google/adk/version.py`
- `adk_dart` CLI parsing/dispatch: `lib/src/dev/cli.dart`
- `adk_dart` deploy target options: `lib/src/cli/cli_deploy.dart`
- `adk_dart` package version: `pubspec.yaml`
- `adk-js` CLI declarations: `../ref/adk-js/dev/src/cli/cli.ts`
- `adk-js` CLI entry (`adk` bin): `../ref/adk-js/dev/package.json`
- `adk-go` CLI root/deploy commands: `../ref/adk-go/cmd/adkgo/internal/root/root.go`, `../ref/adk-go/cmd/adkgo/internal/deploy/deploy.go`, `../ref/adk-go/cmd/adkgo/internal/deploy/cloudrun/cloudrun.go`
- `adk-java` CLI-adjacent surface (Maven goal): `../ref/adk-java/maven_plugin/src/main/java/com/google/adk/maven/WebMojo.java`, `../ref/adk-java/maven_plugin/README.md`
- Upstream SHA snapshots: `reports/adk-python/latest.md`, `reports/adk-js/latest.md`, `reports/adk-go/latest.md`, `reports/adk-java/latest.md`
