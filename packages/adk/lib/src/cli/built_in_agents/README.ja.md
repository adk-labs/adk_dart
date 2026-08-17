# Agent Builder Assistant

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

YAML 構成で ADK マルチエージェントを設計・生成するインテリジェントアシスタントです。

## Quick Start

### Run with ADK Web

```bash
adk web src/google/adk/agent_builder_assistant
```

### Programmatic Usage

```python
agent = AgentBuilderAssistant.create_agent()

agent = AgentBuilderAssistant.create_agent(
    model="gemini-2.5-pro",
    schema_mode="query",
    working_directory="/path/to/project"
)
```

## Core Capabilities

- Requirement analysis and multi-agent architecture suggestions
- AgentConfig schema-compliant YAML generation/validation
- Multi-file read/write/delete with backups
- Project structure exploration and path recommendations
- Session-scoped root directory binding
- Dynamic ADK source/schema discovery

## Schema Modes

- `embedded`: schema embedded, faster but higher token usage
- `query`: dynamic schema query via tools, lower initial token usage

## Tool Ecosystem (Summary)

- File ops: `read_config_files`, `write_config_files`, `read_files`, `write_files`, `delete_files`
- Project analysis: `explore_project`, `resolve_root_directory`
- ADK context: `google_search`, `url_context`, `search_adk_source`

## Note

This is a localized summary. For full details and examples, see [README.md](README.md).
