# Skills Parity Work Unit (2026-03-01 09:42:33)

## Scope
- Dart target:
  - `lib/src/skills/skill.dart`
  - `lib/src/skills/prompt.dart`
  - `lib/adk_dart.dart`
  - `pubspec.yaml`
  - `test/skills_models_test.dart`
  - `test/skills_utils_test.dart`
  - `test/skills_prompt_test.dart`
- Python reference:
  - `ref/adk-python/src/google/adk/skills/models.py`
  - `ref/adk-python/src/google/adk/skills/_utils.py`
  - `ref/adk-python/src/google/adk/skills/prompt.py`
  - `ref/adk-python/src/google/adk/skills/__init__.py`

## Parity gaps addressed
1. Name normalization mismatch (`NFKC`).
2. SKILL.md frontmatter delimiter handling mismatch.
3. Resource loading error handling mismatch.
4. XML escape output mismatch for apostrophe entity.
5. Deprecated compatibility symbol exposure mismatch.

## Implemented changes
1. Full NFKC normalization for frontmatter name.
   - Added dependency `unorm_dart`.
   - Replaced partial normalization with `unorm.nfkc(...)` before regex validation.
2. SKILL.md parser behavior aligned to Python split semantics.
   - Requires file content to start with `---` at byte 0.
   - Frontmatter closes at first subsequent `---` substring after opening delimiter.
3. Resource loading behavior aligned.
   - `_loadDir` now reads raw bytes and decodes UTF-8 with `allowMalformed: false`.
   - Continues to skip malformed-UTF8 files (`FormatException`) only.
   - No longer swallows generic filesystem read errors.
4. Error surface cleanup for validator output.
   - Added `_formatSkillError(...)` to avoid type-prefixed noise in validation messages.
5. XML escape parity tweak.
   - Apostrophe escape changed from `&apos;` to `&#x27;`.
6. Deprecated constant alias parity.
   - Added `DEFAULT_SKILL_SYSTEM_INSTRUCTION` alias in skills prompt surface.
   - Exported skills wrappers (`models.dart`, `prompt.dart`, `_utils.dart`) from package root.

## Tests added/updated
- `test/skills_models_test.dart`
  - Added compatibility-character NFKC normalization case.
- `test/skills_utils_test.dart`
  - Added strict frontmatter-start test.
  - Added first-subsequent-delimiter parsing case.
  - Added resource read filesystem-error propagation case.
- `test/skills_prompt_test.dart`
  - Added apostrophe escape parity assertion.
  - Added deprecated constant alias assertion.

## Validation
- `dart analyze` for modified skills files/tests: passed.
- Targeted skills/session/memory verification bundle: passed.
