# 17. Context Caching & Compaction

`ContextCacheConfig`를 활용하여 장기 대화 및 대용량 문서 분석 시 Gemini Context Cache를 재사용함으로써 토큰 비용을 절감하고 레이턴시를 단축하는 예제입니다.

## 실행 방법

```bash
cd examples/17_context_caching_and_compaction
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```
