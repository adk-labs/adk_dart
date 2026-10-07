# 19. Skills & Output Artifact Persistence

Demonstrates loading modular `SKILL.md` directories, binding `SkillToolset` with `saveOutputArtifacts: true`, and safely injecting binary/text artifacts into agent instructions via `injectSessionState` and `asSafePartForLlm`.

## Execution

```bash
cd examples/19_skills_and_output_artifacts
dart pub get
dart run bin/main.dart
```

---

### 한국어
로컬 `SKILL.md` 디렉토리에서 에이전트 스킬을 로드하고, `SkillToolset(saveOutputArtifacts: true)`을 통해 스크립트 실행 결과 파일을 아티팩트 서비스에 자동 저장하며, `injectSessionState` 및 `asSafePartForLlm`으로 아티팩트를 안전하게 프롬프트에 주입하는 예제입니다.

### 日本語
ローカルの `SKILL.md` ディレクトリからエージェントスキルを読み込み、`SkillToolset(saveOutputArtifacts: true)` によってスクリプト実行結果ファイルをアーティファクトサービスへ自動保存し、`injectSessionState` と `asSafePartForLlm` で安全にプロンプトへ注入するサンプルです。

### 中文
演示从本地 `SKILL.md` 目录加载智能体技能、通过 `SkillToolset(saveOutputArtifacts: true)` 将脚本输出文件自动持久化至工件服务，以及使用 `injectSessionState` 与 `asSafePartForLlm` 安全注入工件的示例。
