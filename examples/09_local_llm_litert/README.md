# 09. On-Device Gemma (LiteRT-LM Native FFI)

Demonstrates zero-dependency, hardware-accelerated on-device Gemma inference leveraging Google LiteRT-LM Native C ABI bindings over `dart:ffi`.

## Execution

```bash
cd examples/09_local_llm_litert
dart pub get
dart run bin/main.dart
```

---

### 한국어
Google LiteRT-LM 네이티브 C ABI를 `dart:ffi`로 직접 바인딩하여 네트워크 통신 및 외부 런타임 종속성 없이 NPU/GPU 가속 기반 온디바이스 Gemma 추론을 수행하는 예제입니다.

### 日本語
Google LiteRT-LM ネイティブ C ABI を `dart:ffi` 経由で直接バインドし、外部依存関係なしに NPU/GPU 加速オンデバイス Gemma 推論を実行するサンプルです。

### 中文
通过 `dart:ffi` 直接绑定 Google LiteRT-LM 原生 C ABI，在无外部依赖且零网络请求的情况下，利用 NPU/GPU 硬件加速在设备端直接运行 Gemma 推理的示例。
