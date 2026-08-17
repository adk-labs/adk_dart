# Agent Builder Assistant

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

YAML 설정 기반 ADK 멀티 에이전트 시스템을 설계/생성하는 지능형 어시스턴트입니다.

## 빠른 시작

### ADK Web으로 실행

```bash
adk web src/google/adk/agent_builder_assistant
```

### 프로그래밍 방식 사용

```python
agent = AgentBuilderAssistant.create_agent()

agent = AgentBuilderAssistant.create_agent(
    model="gemini-2.5-pro",
    schema_mode="query",
    working_directory="/path/to/project"
)
```

## 주요 기능

- 요구사항 분석 및 멀티 에이전트 아키텍처 제안
- AgentConfig 스키마 호환 YAML 생성/검증
- 멀티 파일 읽기/쓰기/삭제 및 백업
- 프로젝트 구조 탐색 및 권장 경로 제안
- 세션 단위 루트 디렉터리 바인딩
- ADK 소스/스키마 동적 탐색

## 스키마 모드

- `embedded`: 스키마 내장, 빠르지만 토큰 사용량 높음
- `query`: 도구로 동적 조회, 초기 토큰 사용량 낮음

## 도구 생태계 (요약)

- 파일 작업: `read_config_files`, `write_config_files`, `read_files`, `write_files`, `delete_files`
- 프로젝트 분석: `explore_project`, `resolve_root_directory`
- ADK 지식 컨텍스트: `google_search`, `url_context`, `search_adk_source`

## 참고

이 문서는 요약본입니다. 전체 설명/예시/규약은 [README.md](README.md)를 참고하세요.
