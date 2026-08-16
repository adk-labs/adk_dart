# 17. Context Caching & Compaction

Demonstrates long-context token optimization and latency reduction using `ContextCacheConfig` with Gemini.

## How to Run

```bash
cd examples/17_context_caching_and_compaction
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`ContextCacheConfig`를 활용하여 장기 대화 및 대용량 문서 분석 시 Gemini Context Cache를 재사용함으로써 토큰 비용을 절감하고 레이턴시를 단축하는 예제입니다.

### 日本語
`ContextCacheConfig` を活用して、長期対話や大規模ドキュメント分析時に Gemini Context Cache を再利用し、トークンコストを削減してレイテンシを短縮するサンプルです。

### 中文
利用 `ContextCacheConfig` 在长对话与海量文档分析中复用 Gemini Context Cache，从而降低 Token 成本并减少延迟的示例。
