# 04. Local Environment

Demonstrates providing agents with isolated host execution capabilities, subprocess I/O pipes, and local filesystem abstraction via `LocalEnvironment`.

## Execution

```bash
cd examples/04_local_environment
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`LocalEnvironment`를 통해 호스트 서브프로세스 쉘 커맨드 실행, 표준 입출력(stdio) 파이핑 및 파일시스템 I/O 도구를 에이전트에 주입하는 런타임 환경 연동 예제입니다.

### 日本語
`LocalEnvironment` を介して、ホストサブプロセスシェルコマンド実行、標準入出力 (stdio) パイプ処理、およびファイルシステム I/O ツールをエージェントに注入する環境統合サンプルです。

### 中文
通过 `LocalEnvironment` 为智能体注入宿主子进程 Shell 命令执行、标准输入输出 (stdio) 管道及文件系统 I/O 工具的运行时环境集成示例。
