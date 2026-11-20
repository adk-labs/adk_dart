# ADK Python Daily Change Report

- Date (UTC): 2026-11-20
- Source: `google/adk-python`
- Latest SHA: `e636d58895ebf4bbafed9bb3319089986ab48196`
- Previous SHA: `0c85ab01c91d63e8b688ac281019d72024ec6183`

## Summary

- New commits: 6

## Commits

- [e636d588](https://github.com/google/adk-python/commit/e636d58895ebf4bbafed9bb3319089986ab48196) chore: merge release v2.15.0 to main (Wei Sun (Jack), 2026-11-20)
- [9efe1252](https://github.com/google/adk-python/commit/9efe1252791a76a0eaaa60e72af1c3b2046fa581) feat: add GroundingPlugin for grounding verification (Google Team Member, 2026-11-20)
- [c81876a4](https://github.com/google/adk-python/commit/c81876a49911745248f2b774c02770ed211ff460) test(workflow): add integration tests for in-place child retries (Thomas Zettl, 2026-11-19)
- [f04b5fe4](https://github.com/google/adk-python/commit/f04b5fe424dbe2c8368682b54bc40ba070a0148d) fix(workflow): retry a failed workflow child in place (Thomas Zettl, 2026-11-19)
- [37de74df](https://github.com/google/adk-python/commit/37de74df1f7f13e013ca354471c12cb6ec6659d2) ci: close only the PR an import's Merge line names (George Weale, 2026-11-19)
- [55b826e3](https://github.com/google/adk-python/commit/55b826e32d153af8442f52219cf7027d1b587689) chore: update telemetry owner (Kacper Jawoszek, 2026-11-19)

## Changed Files

- `M	.agents/skills/adk-architecture/references/architecture-node-runner.md`
- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `M	.github/workflows/copybara-pr-handler.yml`
- `M	CHANGELOG.md`
- `M	contributing/samples/adk_team/component_owners.py`
- `M	docs/guides/README.md`
- `A	docs/guides/integrations/discovery_engine/grounding_plugin/index.md`
- `M	docs/guides/workflow/parallel_worker/index.md`
- `M	docs/guides/workflow/retry_config/index.md`
- `A	scripts/find_imported_prs.py`
- `M	src/google/adk/integrations/discovery_engine/__init__.py`
- `M	src/google/adk/integrations/discovery_engine/_check_grounding_client.py`
- `A	src/google/adk/integrations/discovery_engine/_plugin.py`
- `M	src/google/adk/integrations/discovery_engine/_types.py`
- `M	src/google/adk/version.py`
- `M	src/google/adk/workflow/_base_node.py`
- `M	src/google/adk/workflow/_node_runner.py`
- `M	src/google/adk/workflow/_retry_config.py`
- `M	src/google/adk/workflow/_workflow.py`
- `M	tests/unittests/integrations/discovery_engine/test_check_grounding_client.py`
- `A	tests/unittests/integrations/discovery_engine/test_plugin.py`
- `A	tests/unittests/scripts/test_find_imported_prs.py`
- `M	tests/unittests/workflow/test_node_runner_failure.py`
- `M	tests/unittests/workflow/test_workflow_failures.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
- `M	tests/unittests/workflow/test_workflow_parallel_worker.py`
