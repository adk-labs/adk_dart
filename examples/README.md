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

### 빠른 시작

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> 예제 `02` ~ `07`은 실행 전 `GEMINI_API_KEY` 환경 변수를 설정해야 합니다.
> 예제 `08`, `09`는 로컬/온디바이스 모델을 사용하므로 API 키가 필요하지 않습니다.
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

### Quick Start

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> Examples `02` through `07` require a `GEMINI_API_KEY` environment variable before running.
> Examples `08` and `09` use local/on-device models and do not require an API key.
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

### クイックスタート

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> サンプル `02` ～ `07` を実行する前に、環境変数 `GEMINI_API_KEY` を設定してください。
> サンプル `08`、`09` はローカル/オンデバイスモデルを使用するため、API キーは不要です。
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```

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

### 快速开始

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> 示例 `02` 至 `07` 在运行前需要设置环境变量 `GEMINI_API_KEY`。
> 示例 `08` 和 `09` 使用本地/设备端模型，无需 API 密钥。
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```
