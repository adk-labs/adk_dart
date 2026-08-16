# 17. Context Caching & Compaction

Demonstrates long-context KV-cache reuse, token compaction algorithms, and latency reduction using Gemini `ContextCacheConfig`.

## Execution

```bash
cd examples/17_context_caching_and_compaction
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`ContextCacheConfig`를 활용하여 장기 대화 및 대용량 코드베이스/문서 분석 시 Gemini 서버 측 KV-Cache를 재사용하고, 캐시 TTL/인터벌 설정을 통해 인풋 토큰 비용과 TTFT(Time-to-First-Token) 레이턴시를 획기적으로 단축하는 예제입니다.

### 日本語
`ContextCacheConfig` を活用して、長期対話や大規模コードベース/ドキュメント解析時に Gemini サーバー側の KV-Cache を再利用し、キャッシュ TTL/インターバル設定によって入力トークンコストと TTFT (Time-to-First-Token) レイテンシを劇的に短縮するサンプルです。

### 中文
利用 `ContextCacheConfig` 在长对话与超大规模代码库/文档分析中复用 Gemini 服务端 KV-Cache，并通过缓存 TTL/间隔配置大幅降低输入 Token 开销与 TTFT (首字延迟) 的示例。
