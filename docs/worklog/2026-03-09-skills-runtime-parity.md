# 2026-03-09 Skills Runtime Parity

## Scope
- Match the latest `adk-python` skills runtime behavior where Dart still diverged.
- Close the gaps around activated skills, dynamic additional tools, binary resources, and shared skill exports.

## Work Units

### 1. Skill model widening
- Widened `Frontmatter.metadata` from string-only values to structured metadata.
- Widened `Resources.references` and `Resources.assets` to support either text or binary payloads.
- Added binary accessors for references and assets.
- Preserved local directory loading for text resources while keeping binary assets available.

### 2. Skill toolset runtime parity
- `load_skill` now records activated skills under `_adk_activated_skill_<agent_name>`.
- `SkillToolset` now accepts `additionalTools` and resolves them dynamically from `frontmatter.metadata['adk_additional_tools']`.
- `load_skill_resource` now returns a binary-status payload for non-text resources instead of flattening bytes to text.
- `load_skill_resource.processLlmRequest()` now injects binary resources into the outgoing `LlmRequest` as inline data.
- Script materialization now preserves binary resources when bundling skill files for execution.

### 3. Export/runtime alignment
- Unified public exports onto `skill_runtime.dart` so package consumers and `SkillToolset` use the same `Skill`/`Frontmatter` runtime types.
- Added Web-safe stubs for directory-backed skill utility functions so conditional exports stay type-aligned.

### 4. Verification
- `dart analyze lib/src/skills/skill.dart lib/src/skills/skill_web.dart lib/src/skills/_utils.dart lib/src/skills/models.dart lib/src/skills/prompt.dart lib/src/tools/skill_toolset.dart test/skill_toolset_parity_test.dart test/skills_models_test.dart test/skills_utils_test.dart`
- `dart test test/skill_toolset_parity_test.dart test/skills_models_test.dart test/skills_utils_test.dart`
- Remaining analyzer note is a pre-existing deprecated constant naming info in `lib/src/skills/prompt.dart`.
