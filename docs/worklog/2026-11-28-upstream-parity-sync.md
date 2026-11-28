# 2026-11-28 Upstream Parity Sync (`2026.11.28`)

## Upstream Range
- `adk-python`: `03725e8c67ca27b2c07569797a0c18e867e0b217..bee78e7ce1bc1bfd16cccb0d0f8190ca6d401871` (`adkVersion = '2.15.1'`)
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, no new commits; `main-PJ4DBNMP.js` already synced)

## Task-Unit Commits
1. `94cc9ae8` — `fix(model_armor): keep ModelArmorPlugin's shared client open on runner close`
   - `bee78e7ce`: Overrode `ModelArmorPlugin.close()` in `lib/src/integrations/model_armor/model_armor.dart` to keep the shared client open when a runner closes.
   - Tests: `test/upstream_nov28_model_armor_close_parity_test.dart`, `test/full_python_port_parity_test.dart`, `test/upstream_nov24_transient_instructions_and_live_screening_test.dart` (`42/42` passed).

## Release
- Version: `2026.11.28` (`adkVersion = '2.15.1'`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
