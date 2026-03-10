# 2026-03-10 BigQuery Analytics Views Parity

## Scope

Closed the remaining BigQuery analytics plugin parity gaps that fit the current
Dart plugin architecture by adding trace ID override support and a concrete
analytics-view creation surface.

## Work Units

### 1. Trace ID override support

- Extended `EventData` with `traceIdOverride`.
- Logged rows now prefer an explicit trace ID override before falling back to
  the invocation trace.

### 2. Analytics view creation surface

- Added `createViews` to `BigQueryLoggerConfig`.
- Added `BigQueryAnalyticsViewExecutor`.
- `BigQueryAgentAnalyticsPlugin` now:
  - auto-creates per-event-type analytics views on startup when enabled
  - exposes `createAnalyticsViews()` for manual refresh
  - generates deterministic `CREATE OR REPLACE VIEW` statements for the
    configured project, dataset, and table

### 3. Regression coverage

- Added BigQuery plugin tests for:
  - automatic view creation on startup
  - disabling view creation via `configOverrides`
  - manual view refresh using the same generated statements

## Verification

- `dart analyze lib/src/plugins/bigquery_agent_analytics_plugin.dart test/bigquery_agent_analytics_plugin_parity_test.dart`
- `dart test test/bigquery_agent_analytics_plugin_parity_test.dart`
