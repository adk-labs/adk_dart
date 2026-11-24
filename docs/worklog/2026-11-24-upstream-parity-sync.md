# 2026-11-24 Upstream Parity Sync (`2026.11.24`)

## Upstream Range
- `adk-python`: `4d9e2c75f92305b335f8e66f8b4a8ea99f13017f..54fc37e5fab77f2cfc02fd02f8e6019d288d3920` (`adkVersion = '2.15.0'`)
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, no new commits; `main-PJ4DBNMP.js` already synced)

## Task-Unit Commits
1. `2b9cb720` — `feat(skills): add loadSkillFromMarkdown to build a skill from SKILL.md text`
   - `6686413c2`: Added `loadSkillFromMarkdown` in `lib/src/skills/skill.dart`, `skill_web.dart`, `_utils.dart`.
   - Tests: `test/upstream_nov24_skills_markdown_test.dart` (`4/4` passed).
2. `fb257379` — `feat(classifiers): add GeminiDecisionsClassifier for the Gemini Decisions API`
   - `b4ae4fb8d`: Added `lib/src/labs/classifiers/gemini_decisions_classifier.dart`, exported via `classifiers.dart`, and fixed `runWithClientLabelContext` error scoping in `base_classifier.dart`.
   - Tests: `test/upstream_nov24_gemini_decisions_classifier_test.dart` + `test/classifiers_test.dart` (`39/39` passed).
3. `4ee7610d` — `feat(cli): warn on duplicate Agent Engine display name and add --update_if_exists`
   - `84cb0742b`: Added duplicate `display_name` warning and `--update_if_exists` / `--update-if-exists` option to `packages/adk/lib/src/cli/cli_deploy.dart` and `cli_tools_click.dart`.
   - Tests: `packages/adk/test/upstream_nov24_cli_deploy_update_if_exists_test.dart` + CLI deploy suites (`50/50` passed).
4. `595fba1d` — `fix(telemetry): record a Gemini inference once when the google-genai instrumentor is installed`
   - `8c0d2f880`: Added `lib/src/telemetry/_genai_instrumentor.dart` and updated `tracing.dart` / `metrics.dart`.
   - Tests: `test/upstream_nov24_telemetry_genai_instrumentor_test.dart` + 9 telemetry suites (`134/134` passed).
5. `19fec486` — `fix(models,flows,plugins): track transient instructions, gate dynamic routing, and copy live screening config`
   - `9c22a89fe`, `17c4a10af`: Added transient instruction tracking on `LlmRequest`, `supportsDynamicInstructionRouting` gating across models/live/flows, plugin transient-content awareness, and request-scoped field copying during live user input screening.
   - Tests: `test/upstream_nov24_transient_instructions_and_live_screening_test.dart` + 8 related suites (`84/84` passed).

## Release
- Version: `2026.11.24` (`adkVersion = '2.15.0'`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
