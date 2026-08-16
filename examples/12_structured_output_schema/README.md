# 12. Structured Output Schema

Demonstrates constraining model generation to strict JSON Schema specifications via `outputSchema`, guaranteeing typed deserialization and deterministic payload parsing.

## Execution

```bash
cd examples/12_structured_output_schema
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`outputSchema`를 사용하여 LLM 토큰 디코딩 단계에서 JSON Schema 구문 트리를 강제하고, 타입 안전한 엔티티로 무결점 역직렬화를 보장하는 구조화된 출력 예제입니다.

### 日本語
`outputSchema` を使用して LLM トークン生成時に JSON Schema 構文木を強制し、型安全なエンティティへの無欠損逆シリアル化を保証する構造化出力サンプルです。

### 中文
使用 `outputSchema` 在 LLM Token 生成阶段强制约束 JSON Schema 语法树，并确保类型安全反序列化为实体对象的结构化输出示例。
