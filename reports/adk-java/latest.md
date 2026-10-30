# ADK Java Daily Change Report

- Date (UTC): 2026-10-30
- Source: `google/adk-java`
- Latest SHA: `a4c8ac1ef53543b3a00075899b6499b1874bc90d`
- Previous SHA: `7391fa836e8896787eb3f690875152f9f84bcec3`

## Summary

- New commits: 5

## Commits

- [a4c8ac1e](https://github.com/google/adk-java/commit/a4c8ac1ef53543b3a00075899b6499b1874bc90d) feat(workflow): add NodeExecutionException as the base of NodeTimeoutException (Damian Momot, 2026-10-30)
- [fb4c9160](https://github.com/google/adk-java/commit/fb4c9160b359ee85a32c81da85289264c516b87d) feat(workflow): let RetryConfig match exceptions by class (Damian Momot, 2026-10-30)
- [a0178791](https://github.com/google/adk-java/commit/a0178791015d388b3bad12b6a9f3bade6a6b302e) fix: let a timeout cancel the node a workflow is starting (Damian Momot, 2026-10-30)
- [0c661e11](https://github.com/google/adk-java/commit/0c661e11f76e6eb385930ecf14df6a222444d202) fix: fail a timed-out node with NodeTimeoutException (Damian Momot, 2026-10-30)
- [64ce48c7](https://github.com/google/adk-java/commit/64ce48c742eb423671f2c36696fcf3986f791c73) fix: harden disabled mode, config checks and error capture (Google Team Member, 2026-10-29)

## Changed Files

- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/BigQueryAgentAnalyticsPlugin.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/BigQueryLoggerConfig.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/PluginState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeConfig.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeExecutionException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeTimeoutException.java`
- `M	core/src/main/java/com/google/adk/workflow/RetryConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/BigQueryAgentAnalyticsPluginTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/BigQueryLoggerConfigTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/PluginStateTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	core/src/test/java/com/google/adk/workflow/RetryConfigTest.java`
- `M	core/src/test/java/com/google/adk/workflow/SchedulerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
