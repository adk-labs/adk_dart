# Parity Work Unit: Skills

## Scope
- Python reference: `ref/adk-python/src/google/adk/skills/*`
- Dart target: `lib/src/skills/*`

## Implemented
- Replaced ad-hoc frontmatter parser with YAML parser (`package:yaml`) for Python `yaml.safe_load` parity.
- Added symlink-resolved directory validation/loading (`resolveSymbolicLinksSync`) to match Python `Path.resolve()` behavior.
- Added name normalization step (NFKC-like compatibility normalization for common full-width ASCII forms) before kebab-case validation.
- Added unknown frontmatter field preservation (`extraFields`) and round-trip emission through `Frontmatter.toMap()`.

## Tests
- Updated `test/skills_models_test.dart`
  - extra field preservation round-trip
  - normalization behavior test
- Updated `test/skills_utils_test.dart`
  - YAML block/folded scalar parsing
  - symlinked directory loading
- Updated `test/skill_toolset_parity_test.dart`
  - `load_skill` response preserves extra frontmatter fields

## Validation
- `dart test test/skills_models_test.dart test/skills_utils_test.dart test/skills_prompt_test.dart test/skill_toolset_parity_test.dart`
- `dart analyze lib/src/skills/skill.dart test/skills_models_test.dart test/skills_utils_test.dart test/skill_toolset_parity_test.dart`
- All passed.
