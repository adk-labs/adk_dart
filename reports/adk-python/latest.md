# ADK Python Daily Change Report

- Date (UTC): 2026-11-25
- Source: `google/adk-python`
- Latest SHA: `9fd6b330e6cd5d02bd3604d8e8a31fced17b0286`
- Previous SHA: `825a44c5dfb72cd14d5d037a8f42a27c7bf62292`

## Summary

- New commits: 7

## Commits

- [9fd6b330](https://github.com/google/adk-python/commit/9fd6b330e6cd5d02bd3604d8e8a31fced17b0286) fix(plugins): expose lazy exports in dir() for Sphinx docs (Haiyuan Cao, 2026-11-25)
- [5d505b31](https://github.com/google/adk-python/commit/5d505b315e75ce531cb48e036e1aac4dd7b3d790) test: drop agent modules CLI utils tests leave in sys.modules (Jason Zhang, 2026-11-25)
- [276b7e0e](https://github.com/google/adk-python/commit/276b7e0e65feb2f31001882702ef476126af34e0) feat(optimization): add multi-objective GridSearchAgentOptimizer (Taylor Clancy Behmke, 2026-11-25)
- [d723cb87](https://github.com/google/adk-python/commit/d723cb87b9051d451e7c67d8ea20fe0f6b42be80) feat(optimization): add agent tree cloner for dotted parameter overrides (Taylor Clancy Behmke, 2026-11-25)
- [4e3aff79](https://github.com/google/adk-python/commit/4e3aff79a209ccfd5e1c1a8ea92239e5cfd7b4d5) chore: merge release v2.15.1 to main (adk-bot, 2026-11-25)
- [3e322e9a](https://github.com/google/adk-python/commit/3e322e9a988d6360508e7f6c9fa68983741bea23) fix(plugins): resolve per-turn scoped_system_prompt in BQAA eval SQL (Haiyuan Cao, 2026-11-25)
- [851b7707](https://github.com/google/adk-python/commit/851b7707ad0af9d6ee248a70f836a1388f501281) fix(plugins): add tiebreakers and SessionRollup root_agent in BQAA eval SQL (Haiyuan Cao, 2026-11-24)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	CHANGELOG.md`
- `M	docs/guides/plugins/bigquery_agent_analytics_eval_sql/index.md`
- `M	src/google/adk/features/_feature_registry.py`
- `A	src/google/adk/optimization/_agent_tree_cloner.py`
- `A	src/google/adk/optimization/_grid_search_agent_optimizer.py`
- `M	src/google/adk/plugins/__init__.py`
- `M	src/google/adk/plugins/_bigquery_agent_analytics_eval_sql.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_session_query_v1.sql`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_turn_query_v1.sql`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_view_ctes_v1.sql`
- `M	src/google/adk/version.py`
- `A	tests/unittests/cli/utils/conftest.py`
- `M	tests/unittests/cli/utils/test_agent_loader.py`
- `A	tests/unittests/optimization/agent_tree_cloner_test.py`
- `A	tests/unittests/optimization/grid_search_agent_optimizer_test.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_sql_sync.py`
- `M	tests/unittests/plugins/test_plugins_package.py`
