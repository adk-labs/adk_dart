# ADK Dart Examples

> 🇰🇷 [한국어](#한국어) | 🇺🇸 [English](#english) | 🇯🇵 [日本語](#日本語) | 🇨🇳 [中文](#中文)

---

## 한국어

ADK (Agent Development Kit) Dart 패키지를 사용하여 AI 에이전트를 개발하고 활용하는 다양한 단계별 예제 프로젝트 모음입니다.

각 예제는 사용자가 쉽게 다운로드하여 단독 프로젝트로 컴파일 및 동작시킬 수 있는 완성형 **Dart CLI 프로젝트** 형태로 구성되어 있습니다.

### 예제 목록

1. **[01_echo_agent](./01_echo_agent)** — 기초 에이전트 및 Runner 구성
2. **[02_weather_agent](./02_weather_agent)** — FunctionTool을 이용한 도구 사용(Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — 멀티 에이전트 Hand-off 오케스트레이션 + Google 검색
4. **[04_local_environment](./04_local_environment)** — LocalEnvironment 실행 환경 연동
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 워크플로우 Fan-Out / Fan-In
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — 런타임 동적 노드 오케스트레이션
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — ManagedAgent (원격 에이전트) 구성
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — 로컬 Ollama / LiteLLM 서버 연동
9. **[09_local_llm_litert](./09_local_llm_litert)** — 온디바이스 Gemma (LiteRT-LM) 추론
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — Streamable HTTP MCP 서버 및 도구 연동
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — GetUserChoiceTool 기반 휴먼 인 더 루프(HITL) 상호작용
12. **[12_structured_output_schema](./12_structured_output_schema)** — outputSchema 기반 구조화된 JSON 응답 생성
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — Agent-to-Agent (A2A) 표준 프로토콜 및 AgentCard 연동
14. **[14_code_execution_agent](./14_code_execution_agent)** — 샌드박스 코드 실행(Code Execution) 기반 연산 에이전트
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — LocalEvalService 기반 자동화된 에이전트 평가 및 벤치마킹
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — 이미지/바이트 멀티모달 입력 처리
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — ContextCacheConfig 기반 컨텍스트 캐싱 최적화
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — SqliteSessionService 기반 영속 세션 관리

### 빠른 시작

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> Gemini 연동 예제(`02` ~ `07`, `10` ~ `12`, `14`, `16`, `17`)는 실행 전 `GEMINI_API_KEY` 환경 변수를 설정해야 합니다.
> 스텁 및 로컬 예제(`01`, `08`, `09`, `13`, `15`, `18`)는 외부 API 키 없이 즉시 실행 가능합니다.
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```

---

## English

A collection of step-by-step example projects for building and running AI agents with the ADK (Agent Development Kit) Dart package.

Each example is a self-contained **Dart CLI project** you can download and run immediately.

### Example List

1. **[01_echo_agent](./01_echo_agent)** — Basic agent & runner setup
2. **[02_weather_agent](./02_weather_agent)** — Tool Calling with FunctionTool
3. **[03_multi_agent_search](./03_multi_agent_search)** — Multi-agent Hand-off orchestration + Google Search
4. **[04_local_environment](./04_local_environment)** — LocalEnvironment integration
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 Workflow Fan-Out / Fan-In
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — Runtime dynamic node orchestration
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — ManagedAgent (remote agent) setup
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — Local Ollama / LiteLLM server integration
9. **[09_local_llm_litert](./09_local_llm_litert)** — On-device Gemma inference via LiteRT-LM
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — Streamable HTTP MCP server & tool integration
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — Human-In-The-Loop interactive choices with GetUserChoiceTool
12. **[12_structured_output_schema](./12_structured_output_schema)** — Typed JSON responses via outputSchema
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — Agent-to-Agent (A2A) protocol & AgentCard
14. **[14_code_execution_agent](./14_code_execution_agent)** — Code Execution agent for numerical problem-solving
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — Automated evaluation & benchmarking via LocalEvalService
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — Multimodal input processing (Images & Text)
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — Context caching optimization with ContextCacheConfig
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — Persistent sessions across restarts with SqliteSessionService

### Quick Start

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> Gemini-backed examples (`02` ~ `07`, `10` ~ `12`, `14`, `16`, `17`) require a `GEMINI_API_KEY` environment variable.
> Stub & local examples (`01`, `08`, `09`, `13`, `15`, `18`) run offline without an API key.
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```

---

## 日本語

ADK (Agent Development Kit) Dart パッケージを使用して AI エージェントを開発・活用するための、段階的なサンプルプロジェクト集です。

各サンプルは、ダウンロードしてすぐにスタンドアロンプロジェクトとしてコンパイル・実行できる完成形の **Dart CLI プロジェクト**として構成されています。

### サンプル一覧

1. **[01_echo_agent](./01_echo_agent)** — 基本的なエージェントと Runner の構成
2. **[02_weather_agent](./02_weather_agent)** — FunctionTool を使ったツール呼び出し (Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — マルチエージェント Hand-off オーケストレーション + Google 検索
4. **[04_local_environment](./04_local_environment)** — LocalEnvironment 実行環境の連携
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 ワークフロー Fan-Out / Fan-In
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — ランタイム動的ノードオーケストレーション
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — ManagedAgent (リモートエージェント) の設定
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — ローカル Ollama / LiteLLM サーバー連携
9. **[09_local_llm_litert](./09_local_llm_litert)** — LiteRT-LM によるオンデバイス Gemma 推論
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — Streamable HTTP MCP サーバー連携
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — GetUserChoiceTool による Human-In-The-Loop 選択対話
12. **[12_structured_output_schema](./12_structured_output_schema)** — outputSchema による構造化 JSON レスポンス生成
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — A2A 標準プロトコルと AgentCard 連携
14. **[14_code_execution_agent](./14_code_execution_agent)** — コード実行 (Code Execution) による高精度計算エージェント
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — LocalEvalService による自動評価とベンチマーク
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — 画像・バイトデータのマルチモーダル入力処理
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — ContextCacheConfig によるコンテキストキャッシュ最適化
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — SqliteSessionService による永続セッション管理

### クイックスタート

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

---

## 中文

这是一个使用 ADK (Agent Development Kit) Dart 包开发和使用 AI 智能体的分步示例项目合集。

每个示例都是一个完整的 **Dart CLI 项目**，可以直接下载并作为独立项目编译运行。

### 示例列表

1. **[01_echo_agent](./01_echo_agent)** — 基础智能体与 Runner 配置
2. **[02_weather_agent](./02_weather_agent)** — 使用 FunctionTool 进行工具调用 (Tool Calling)
3. **[03_multi_agent_search](./03_multi_agent_search)** — 多智能体 Hand-off 编排 + Google 搜索
4. **[04_local_environment](./04_local_environment)** — LocalEnvironment 执行环境集成
5. **[05_workflow_fan_out_fan_in](./05_workflow_fan_out_fan_in)** — ADK 2.0 工作流 Fan-Out / Fan-In
6. **[06_workflow_dynamic_nodes](./06_workflow_dynamic_nodes)** — 运行时动态节点编排
7. **[07_managed_agent_basic](./07_managed_agent_basic)** — ManagedAgent（远程智能体）配置
8. **[08_local_llm_ollama_litellm](./08_local_llm_ollama_litellm)** — 本地 Ollama / LiteLLM 服务器集成
9. **[09_local_llm_litert](./09_local_llm_litert)** — 通过 LiteRT-LM 进行设备端 Gemma 推理
10. **[10_mcp_streamable_http](./10_mcp_streamable_http)** — Streamable HTTP MCP 协议与远程工具集成
11. **[11_hitl_user_choice](./11_hitl_user_choice)** — 基于 GetUserChoiceTool 的人机协同选择交互
12. **[12_structured_output_schema](./12_structured_output_schema)** — 基于 outputSchema 的类型安全 JSON 输出
13. **[13_a2a_agent_protocol](./13_a2a_agent_protocol)** — Agent-to-Agent (A2A) 标准协议与 AgentCard
14. **[14_code_execution_agent](./14_code_execution_agent)** — 基于代码执行 (Code Execution) 的数值计算智能体
15. **[15_evaluation_llm_judge](./15_evaluation_llm_judge)** — 基于 LocalEvalService 的自动化智能体评测与基准测试
16. **[16_multimodal_gemini](./16_multimodal_gemini)** — 图像与多模态输入处理
17. **[17_context_caching_and_compaction](./17_context_caching_and_compaction)** — 基于 ContextCacheConfig 的上下文缓存优化
18. **[18_sqlite_session_persistence](./18_sqlite_session_persistence)** — 基于 SqliteSessionService 的跨重启会话持久化
