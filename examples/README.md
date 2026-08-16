# ADK Dart Examples Architecture & Showcase

> 🇺🇸 [English](#english) | 🇰🇷 [한국어](#한국어) | 🇯🇵 [日本語](#日本語) | 🇨🇳 [中文](#中文)

---

## English

A collection of standalone, reproducible **Dart CLI projects** demonstrating core architectural patterns, orchestrations, runtime protocols, and model integrations with the ADK (Agent Development Kit) Dart ecosystem.

### Architectural Directory (18 Production Patterns)

1. **[01_echo_agent](./01_echo_agent)** — Custom `BaseLlm` engine implementation, pipeline lifecycle, and `InMemoryRunner` orchestration.
2. **[02_weather_agent](./02_weather_agent)** — Declarative `FunctionTool` binding, schema reflection, and Gemini automated Function/Tool Calling.
3. **[03_multi_agent_search](./03_multi_agent_search)** — Hierarchical multi-agent delegation, autonomous Hand-off state machines, and real-time `googleSearch` grounding.
4. **[04_local_environment](./04_local_environment)** — Sandboxed OS process execution, subprocess I/O piping, and local filesystem abstraction via `LocalEnvironment`.
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 DAG node graph workflows with concurrent parallel branch evaluation (`Fan-Out`) and deterministic barrier joins (`Fan-In`).
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — Runtime dynamic node injection, topological graph mutating, and contextual state propagation.
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — Cloud-native RPC integration with Google Cloud Vertex AI `ManagedAgent` and remote Interactions API.
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — Offline OpenAI-compatible API reverse proxy integration via local Ollama (`:11434`) and LiteLLM (`:4000`).
9. **[09_local_llm_litert](./09_local_llm_litert)** — Zero-dependency on-device Gemma inference leveraging Google LiteRT-LM Native C ABI / `dart:ffi`.
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — Model Context Protocol (MCP) tool discovery and remote invocation via `StreamableHTTPConnectionParams` and `McpToolset`.
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — Interactive Human-In-The-Loop (HITL) execution pause, user disambiguation, and choice resumption via `GetUserChoiceTool`.
12. **[12_structured_output_schema](./12_structured_output_schema)** — Deterministic JSON Schema enforcement, strict type validation, and structured deserialization via `outputSchema`.
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — Open Agent-to-Agent (A2A) standard protocol compliance, `AgentCard` schema publishing, and `A2aAgentExecutor` stream routing.
14. **[14_code_execution_agent](./14_code_execution_agent)** — Sandboxed code generation and runtime AST execution for exact numerical and algorithmic computation via `BuiltInCodeExecutor`.
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — Automated CI/CD agent evaluation, rubric-based LLM-as-a-Judge benchmarking, and trajectory analysis via `LocalEvalService`.
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — Heterogeneous multimodal token stream ingestion (raw image bytes, audio, MIME payloads) via `InlineData` and `Part`.
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — Gemini Context Cache TTL/Interval optimization, token compaction, and high-throughput low-latency long-context analysis via `ContextCacheConfig`.
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — ACID-compliant transaction-safe event store, session rollback/rewind, and cross-process state persistence via `SqliteSessionService`.

### Quick Start

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> Gemini-backed examples (`02` ~ `07`, `10` ~ `12`, `14`, `16`, `17`) require setting the `GEMINI_API_KEY` or `GOOGLE_API_KEY` environment variable:
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```
> Local engine & offline protocol examples (`01`, `08`, `09`, `13`, `15`, `18`) execute purely offline without external API keys.

---

## 한국어

ADK (Agent Development Kit) Dart 프레임워크의 코어 아키텍처 패턴, 런타임 프로토콜, 노드 오케스트레이션 및 모델 인터페이스를 실증하는 **독립형 Dart CLI 프로젝트** 모음입니다.

### 아키텍처 패턴 목록 (18개 프로덕션 패턴)

1. **[01_echo_agent](./01_echo_agent)** — 커스텀 `BaseLlm` 추론 엔진 구현, 파이프라인 수명주기 및 `InMemoryRunner` 오케스트레이션
2. **[02_weather_agent](./02_weather_agent)** — 선언적 `FunctionTool` 바인딩, 스키마 리플렉션 및 Gemini 자동 함수/도구 호출(Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — 계층형 멀티 에이전트 위임, 자율 Hand-off 상태 머신 및 실시간 `googleSearch` 그라운딩
4. **[04_local_environment](./04_local_environment)** — 샌드박스 OS 프로세스 실행, 서브프로세스 I/O 파이핑 및 `LocalEnvironment` 파일시스템 추상화
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 DAG 노드 그래프 워크플로우의 동시 병렬 분기 평가(`Fan-Out`) 및 동기화 배리어 합류(`Fan-In`)
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — 런타임 동적 노드 인젝션, 위상 그래프 변이(Mutation) 및 컨텍스트 상태 전파
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — Google Cloud Vertex AI `ManagedAgent` 클라우드 네이티브 RPC 통신 및 원격 Interactions API 연동
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — 로컬 Ollama (`:11434`) 및 LiteLLM (`:4000`) 리버스 프록시를 통한 OpenAI 호환 오프라인 LLM 연동
9. **[09_local_llm_litert](./09_local_llm_litert)** — Google LiteRT-LM 네이티브 C ABI / `dart:ffi` 기반 무의존성 온디바이스 Gemma 추론
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — `StreamableHTTPConnectionParams` 및 `McpToolset` 기반 Model Context Protocol (MCP) 원격 도구 디스커버리 및 RPC 호출
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — `GetUserChoiceTool` 기반 Human-In-The-Loop (HITL) 런타임 인터럽트, 사용자 분기 처리 및 컨텍스트 재개
12. **[12_structured_output_schema](./12_structured_output_schema)** — `outputSchema` 기반 엄격한 JSON Schema 강제, 정적 타입 검증 및 구조화된 역직렬화
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — 오픈 Agent-to-Agent (A2A) 표준 프로토콜 준수, `AgentCard` 스키마 퍼블리싱 및 `A2aAgentExecutor` 이벤트 라우팅
14. **[14_code_execution_agent](./14_code_execution_agent)** — `BuiltInCodeExecutor` 샌드박스 코드 생성 및 런타임 AST 실행 기반 수치/알고리즘 연산
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — `LocalEvalService` 기반 CI/CD 자동화 에이전트 평가, 루브릭 기반 LLM-as-a-Judge 벤치마킹 및 궤적(Trajectory) 분석
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — `InlineData` 및 `Part` 기반 이기종 멀티모달 토큰 스트림(Raw 이미지 바이트, 오디오, MIME 페이로드) 수신 및 추론
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — `ContextCacheConfig` 기반 Gemini Context Cache TTL/인터벌 최적화, 토큰 압축 및 고처리량 장기 컨텍스트 분석
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — `SqliteSessionService` 기반 ACID 트랜잭션 안전 이벤트 스토어, 세션 롤백/리와인드 및 프로세스 간 영속 상태 관리

### 빠른 시작

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

---

## 日本語

ADK (Agent Development Kit) Dart フレームワークのコアアーキテクチャパターン、ランタイムプロトコル、ノードオーケストレーション、モデルインターフェースを実証する**スタンドアロン Dart CLI プロジェクト**集です。

### アーキテクチャパターン一覧 (18個のプロダクションパターン)

1. **[01_echo_agent](./01_echo_agent)** — カスタム `BaseLlm` 推論エンジンの実装、パイプラインライフサイクル、および `InMemoryRunner` オーケストレーション
2. **[02_weather_agent](./02_weather_agent)** — 宣言的 `FunctionTool` バインディング、スキーマリフレクション、および Gemini 自動関数/ツール呼び出し (Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — 階層型マルチエージェント委譲、自律的 Hand-off ステートマシン、およびリアルタイム `googleSearch` グラウンディング
4. **[04_local_environment](./04_local_environment)** — サンドボックス OS プロセス実行、サブプロセス I/O パイプ処理、および `LocalEnvironment` ファイルシステム抽象化
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 DAG ノードグラフワークフローにおける並列分岐評価 (`Fan-Out`) および同期バリア合流 (`Fan-In`)
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — ランタイム動的ノードインジェクション、トポロジカルグラフ変異 (Mutation)、およびコンテキスト状態伝播
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — Google Cloud Vertex AI `ManagedAgent` クラウドネイティブ RPC 通信およびリモート Interactions API 連携
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — ローカル Ollama (`:11434`) および LiteLLM (`:4000`) リバースプロキシ経由の OpenAI 互換オフライン推論
9. **[09_local_llm_litert](./09_local_llm_litert)** — Google LiteRT-LM ネイティブ C ABI / `dart:ffi` を活用した依存関係ゼロのオンデバイス Gemma 推論
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — `StreamableHTTPConnectionParams` および `McpToolset` による Model Context Protocol (MCP) リモートツールディスカバリと RPC 呼び出し
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — `GetUserChoiceTool` による Human-In-The-Loop (HITL) ランタイム割り込み、ユーザー分岐処理、およびコンテキスト再開
12. **[12_structured_output_schema](./12_structured_output_schema)** — `outputSchema` による厳密な JSON Schema 強制、静的型検証、および構造化逆シリアル化
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — Open Agent-to-Agent (A2A) 標準プロトコル準拠、`AgentCard` スキーマ公開、および `A2aAgentExecutor` イベントルーティング
14. **[14_code_execution_agent](./14_code_execution_agent)** — `BuiltInCodeExecutor` サンドボックスコード生成およびランタイム AST 実行による厳密な数値・アルゴリズム演算
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — `LocalEvalService` による CI/CD 自動エージェント評価、ルーブリックベース LLM-as-a-Judge ベンチマーク、および軌跡 (Trajectory) 分析
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — `InlineData` および `Part` によるマルチモーダルトークンストリーム (Raw 画像バイト、音声、MIME ペイロード) の推論処理
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — `ContextCacheConfig` による Gemini Context Cache TTL/インターバル最適化、トークン圧縮、および高スループット長文コンテキスト解析
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — `SqliteSessionService` による ACID トランザクションセーフなイベントストア、セッションロールバック/リワインド、およびプロセス間永続化

### クイックスタート

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

---

## 中文

演示 ADK (Agent Development Kit) Dart 框架核心架构模式、运行时协议、节点编排与模型接口的**独立 Dart CLI 工程**合集。

### 架构模式列表 (18个生产级模式)

1. **[01_echo_agent](./01_echo_agent)** — 自定义 `BaseLlm` 推理引擎实现、管道生命周期管理与 `InMemoryRunner` 编排
2. **[02_weather_agent](./02_weather_agent)** — 声明式 `FunctionTool` 绑定、模式反射 (Schema Reflection) 与 Gemini 自动化函数/工具调用 (Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — 分层多智能体委托、自主 Hand-off 状态机与实时 `googleSearch` 接地 (Grounding)
4. **[04_local_environment](./04_local_environment)** — 沙箱 OS 进程执行、子进程 I/O 管道传输与 `LocalEnvironment` 文件系统抽象
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 DAG 节点图工作流的并发并行分支评估 (`Fan-Out`) 与同步屏障汇聚 (`Fan-In`)
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — 运行时动态节点注入、拓扑图变异 (Mutation) 与上下文状态传播
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — Google Cloud Vertex AI `ManagedAgent` 云原生 RPC 通信与远程 Interactions API 集成
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — 通过本地 Ollama (`:11434`) 与 LiteLLM (`:4000`) 反向代理实现的 OpenAI 兼容离线大模型推理
9. **[09_local_llm_litert](./09_local_llm_litert)** — 基于 Google LiteRT-LM 原生 C ABI / `dart:ffi` 的零依赖设备端 Gemma 推理
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — 基于 `StreamableHTTPConnectionParams` 和 `McpToolset` 的 Model Context Protocol (MCP) 远程工具发现与 RPC 调用
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — 基于 `GetUserChoiceTool` 的 Human-In-The-Loop (HITL) 运行时中断、用户分支消歧与上下文恢复
12. **[12_structured_output_schema](./12_structured_output_schema)** — 基于 `outputSchema` 的严格 JSON Schema 约束、静态类型校验与结构化反序列化
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — 遵循开放 Agent-to-Agent (A2A) 标准协议、`AgentCard` 模式发布与 `A2aAgentExecutor` 事件流路由
14. **[14_code_execution_agent](./14_code_execution_agent)** — 基于 `BuiltInCodeExecutor` 沙箱代码生成与运行时 AST 执行的数值与算法精准计算
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — 基于 `LocalEvalService` 的 CI/CD 自动化智能体评测、量规基准 LLM-as-a-Judge 测试与轨迹 (Trajectory) 分析
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — 基于 `InlineData` 与 `Part` 的异构多模态 Token 流 (Raw 图像字节、音频、MIME 负载) 推理
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — 基于 `ContextCacheConfig` 的 Gemini Context Cache TTL/间隔优化、Token 压缩与高吞吐低延迟长上下文分析
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — 基于 `SqliteSessionService` 的 ACID 事务安全事件存储、会话回滚/重退 (Rewind) 与跨进程状态持久化

### 快速开始

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```
