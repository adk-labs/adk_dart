# ADK Python Daily Change Report

- Date (UTC): 2026-10-11
- Source: `google/adk-python`
- Latest SHA: `bca4a425b1b0abccddf8af26735773394a808427`
- Previous SHA: `3c31fa5100a617d03a19f8a9495b8b93d2e47628`

## Summary

- New commits: 3

## Commits

- [bca4a425](https://github.com/google/adk-python/commit/bca4a425b1b0abccddf8af26735773394a808427) refactor(agents): remove Python <3.11 merge fallback in ParallelAgent (Shangjie Chen, 2026-10-10)
- [bcac35a6](https://github.com/google/adk-python/commit/bcac35a6efb21f176eef9d28d663db247f4e5afd) fix(workflow): wait for all direct interrupts before rerunning rerun_on_resume nodes (Shangjie Chen, 2026-10-10)
- [531a86a1](https://github.com/google/adk-python/commit/531a86a194c910ec5bfdfc9f7de09be80c5aaada) fix(workflow): wait for in-flight workers on HITL interrupt in ParallelWorker (Shangjie Chen, 2026-10-10)

## Changed Files

- `M	src/google/adk/agents/parallel_agent.py`
- `M	src/google/adk/workflow/_parallel_worker.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	src/google/adk/workflow/utils/_replay_interceptor.py`
- `M	tests/unittests/agents/test_parallel_agent.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
- `M	tests/unittests/workflow/test_workflow_parallel_worker.py`
- `M	tests/unittests/workflow/utils/test_replay_interceptor.py`
