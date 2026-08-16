# 08. Local LLM (Ollama & LiteLLM Proxy)

Demonstrates integrating ADK pipelines with OpenAI-compatible reverse proxies using local Ollama (`http://localhost:11434`) and LiteLLM (`http://localhost:4000`) for air-gapped, zero-egress LLM inference.

## Execution

```bash
cd examples/08_local_llm_ollama_litellm
dart pub get
dart run bin/main.dart
```

---

### 한국어
로컬 호스트의 Ollama(`:11434`) 및 LiteLLM(`:4000`) 프록시 서버와 ADK 파이프라인을 바인딩하여 외부 네트워크 통신이 배제된 에어갭(Air-gapped) 오프라인 환경에서 안전하게 추론하는 예제입니다.

### 日本語
ローカルホストの Ollama (`:11434`) および LiteLLM (`:4000`) プロキシサーバーと ADK パイプラインを接続し、外部通信を遮断したエアギャップ環境で安全に推論を実行するサンプルです。

### 中文
将 ADK 管道与本地主机上的 Ollama (`:11434`) 及 LiteLLM (`:4000`) 代理服务器绑定，在完全隔离外部网络的物理隔绝 (Air-gapped) 环境下安全执行大模型推理的示例。
