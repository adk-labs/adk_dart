# 2026-03-09 BigQuery Search Parity

Scope:
- Follow-up batch after `2026-03-09-python-parity-batch-2.md`
- Targeted deferred gap from `adk-python`:
  - `src/google/adk/tools/bigquery/search_tool.py`
  - `src/google/adk/tools/bigquery/bigquery_toolset.py`
  - `src/google/adk/tools/bigquery/bigquery_credentials.py`

Goal:
- Close the missing `search_catalog` functionality gap so Dart exposes the same
  BigQuery catalog search capability through Dataplex.

## Work Unit 1: BigQuery Credential Scope Alignment

Reason:
- Python now defaults BigQuery credentials to both BigQuery and Dataplex
  scopes.

Implemented:
- Updated `BigQueryCredentialsConfig` default scopes to include:
  - `https://www.googleapis.com/auth/bigquery`
  - `https://www.googleapis.com/auth/dataplex`

Files:
- `lib/src/tools/bigquery/bigquery_credentials.dart`
- `test/tools_google_credentials_configs_parity_test.dart`

## Work Unit 2: Dataplex Catalog Client Runtime

Reason:
- Dart did not have a Dataplex catalog client, so `search_catalog` could not
  be implemented as a functioning tool.

Implemented:
- Added `dataplexUserAgent`
- Added `DataplexSearchEntryResult`
- Added `DataplexCatalogClient` abstraction
- Added factory override hooks for tests
- Added default REST-backed Dataplex catalog client using `curl` and ADC /
  access-token resolution, mirroring the existing BigQuery REST client style

Files:
- `lib/src/tools/bigquery/client.dart`

## Work Unit 3: `search_catalog` Tool

Reason:
- Python added `search_catalog` to BigQuery tools using Dataplex semantic
  search.

Implemented:
- Added `searchCatalog()` tool handler
- Implemented query construction parity for:
  - natural-language prompt
  - project filters
  - dataset filters
  - type filters
  - implicit `system=BIGQUERY` scoping
- Implemented location fallback order:
  - explicit `location`
  - `settings.location`
  - `global`
- Added Dataplex API error mapping

Files:
- `lib/src/tools/bigquery/search_tool.dart`
- `lib/src/tools/bigquery/bigquery.dart`

## Work Unit 4: Toolset Exposure

Reason:
- Python `BigQueryToolset` now exposes `search_catalog`.

Implemented:
- Added `search_catalog` to Dart `BigQueryToolset`

Files:
- `lib/src/tools/bigquery/bigquery_toolset.dart`
- `test/bigquery_parity_test.dart`

## Verification

Static analysis:

```bash
dart analyze \
  lib/src/tools/bigquery/bigquery_credentials.dart \
  lib/src/tools/bigquery/search_tool.dart \
  lib/src/tools/bigquery/bigquery.dart \
  lib/src/tools/bigquery/bigquery_toolset.dart \
  lib/src/tools/bigquery/client.dart \
  test/bigquery_parity_test.dart \
  test/tools_google_credentials_configs_parity_test.dart
```

Result:
- No errors

Tests:

```bash
dart test \
  test/bigquery_parity_test.dart \
  test/tools_google_credentials_configs_parity_test.dart
```

Result:
- All tests passed

## Remaining BigQuery Gaps

This batch closes the missing catalog search gap. Broader BigQuery parity items
outside this batch still include:
- any future Dataplex pagination or advanced entry-shape parity not exercised by
  current upstream tests
- any later upstream BigQuery features beyond the `9d155177` sync range
