# 2026-03-09 Skills GCS Parity

## Scope
- Add GCS-backed skill listing and loading parity to match the latest `adk-python` skills utilities.
- Keep the implementation testable without live network access.

## Work Units

### 1. GCS-backed skill utilities
- Added `SkillGcsStore` abstraction and `LiveSkillGcsStore` implementation.
- Added `listSkillsInGcsDir()` for GCS-backed skill discovery.
- Added `loadSkillFromGcsDir()` for loading `SKILL.md`, references, assets, and scripts from a bucket prefix.
- Reused the existing Google access-token helper for live auth instead of introducing a separate auth path.

### 2. Resource handling parity
- GCS-loaded references and assets now preserve binary payloads instead of forcing UTF-8 text.
- GCS-loaded scripts remain UTF-8-only and binary scripts are skipped.
- Local resource detection was tightened so known binary file types such as `.pdf` stay binary.

### 3. Conditional export alignment
- Added Web stubs for the new GCS skill APIs and storage types so `skill_runtime.dart` keeps a consistent public surface.
- Updated legacy skill utility exports to expose the new GCS entry points.

### 4. Verification
- `dart analyze lib/src/skills/skill.dart lib/src/skills/skill_web.dart lib/src/skills/_utils.dart test/skills_utils_test.dart`
- `dart test test/skills_utils_test.dart test/skill_toolset_parity_test.dart test/skills_models_test.dart`
