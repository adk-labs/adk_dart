# Agent Builder Assistant

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

这是一个用于基于 YAML 配置构建 ADK 多 Agent 系统的智能助手。

## 快速开始

### 通过 ADK Web 运行

```bash
adk web src/google/adk/agent_builder_assistant
```

### 编程方式使用

```python
agent = AgentBuilderAssistant.create_agent()

agent = AgentBuilderAssistant.create_agent(
    model="gemini-2.5-pro",
    schema_mode="query",
    working_directory="/path/to/project"
)
```

## 核心能力

- 需求分析与多 Agent 架构建议
- 生成/校验符合 AgentConfig schema 的 YAML
- 多文件读写删除与备份
- 项目结构分析与路径建议
- 按会话绑定根目录
- 动态发现 ADK 源码与 schema

## Schema 模式

- `embedded`: 内嵌 schema，速度快但 token 开销更高
- `query`: 通过工具动态查询 schema，初始 token 开销更低

## 工具体系（摘要）

- 文件操作: `read_config_files`, `write_config_files`, `read_files`, `write_files`, `delete_files`
- 项目分析: `explore_project`, `resolve_root_directory`
- ADK 知识上下文: `google_search`, `url_context`, `search_adk_source`

## 说明

本文件为本地化摘要。完整细节与示例请参考 [README.md](README.md)。
