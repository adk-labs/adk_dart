# 2026-11-09 Upstream Parity Sync & Release (`2026.11.9`)

## Summary

Synced `adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`, and `packages/flutter_adk` against upstream `adk-python` (`dd7161f7a3875625677b3abbf322c461001c60ba..67b217d00668400383a5dc8ef1b241c8fb114b31`) and `adk-web` (`07a07025a71c86f2c66da39cbef1f441bcdb28d6`), verified and expanded the repository-bundled `.agents/skills/` AI coding agent skills suite, and released `2026.11.9`.

## Upstream Reference Heads

- `adk-python`: `67b217d00668400383a5dc8ef1b241c8fb114b31` (`v2.14.0` + 2 commits)
- `adk-web`: `07a07025a71c86f2c66da39cbef1f441bcdb28d6`

## Key Changes Ported

1. **A2A Unary Task History `finish_task` Resolution (`1cb926d5b`)**:
   - Added `findFinishTaskArgsFromHistory` in `lib/src/agents/remote_a2a_agent.dart` so `RemoteA2aAgent(mode: 'task')` resolves `finish_task` call arguments from `Task.history` in unary (non-streaming) `SendMessageSuccessResponse` payloads when the completed task's final `status.message` only carries the `finish_task` `FunctionResponse`.
   - Updated `AgentTool` (`lib/src/tools/agent_tool.dart`) to inspect `event.hasOutput` (`event.output`) when extracting `finish_task` tool results from `mode: 'task'` sub-agents, and updated `Event.output` setter in `lib/src/events/event.dart` to mark `hasOutput = true`.
2. **Synchronous Metric Evaluator Isolation & `evalClientLabel` Propagation (`67b217d00`)**:
   - Updated `Evaluator.evaluateInvocations` (`lib/src/evaluation/evaluator.dart`) to return `FutureOr<EvaluationResult>`.
   - Updated `LocalEvalService.evaluate` (`lib/src/evaluation/local_eval_service.dart`) and `CustomMetricEvaluator.evaluateInvocations` (`lib/src/evaluation/custom_metric_evaluator.dart`) to schedule synchronous evaluators off the caller frame while propagating the active `evalClientLabel` zone context (`runWithEvalClientLabel`) and preserving `EvalMetric.threshold` on the caller's metric instance.
3. **AI Coding Agent Skills Suite (`.agents/skills/`)**:
   - Verified and updated `.agents/skills/{adk-dart-setup,adk-dart-agent-builder,adk-dart-architecture,adk-dart-cli-and-web,adk-dart-debug,flutter-adk-ui-builder}/SKILL.md` with automated validation tests in `test/repo_agent_skills_test.dart`.
