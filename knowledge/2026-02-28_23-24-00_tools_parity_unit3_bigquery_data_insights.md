# Tools Parity Work Unit 3: BigQuery Data Insights

## Scope
- Target: `lib/src/tools/bigquery/data_insights_tool.dart`
- Goal: close runtime parity gaps around default transport availability, token extraction, and stream parsing behavior.

## Changes
- Implemented a built-in default HTTP execution path for `ask_data_insights`:
  - POSTs to the Gemini Data Analytics endpoint using `HttpClient`
  - emits line-based stream payloads for existing parser flow
  - raises HTTP error details for non-2xx responses
- Updated stream parser behavior to avoid line trimming and follow Python-style line handling semantics.
- Expanded access token extraction compatibility:
  - `GoogleOAuthCredential`
  - `AuthCredential` (OAuth2 token)
  - map token keys (`token`, `access_token`, `accessToken`)
  - raw string token
- Kept existing output contract unchanged (`status`, `response`, `error_details`).

## Tests
- Updated `test/bigquery_parity_test.dart` to validate `AuthCredential` token path for `ask_data_insights`.

## Validation
- Command:
  - `dart test test/bigquery_parity_test.dart`
- Result:
  - All tests passed.

## Notes
- This unit enables out-of-the-box network behavior without mandatory stream-provider injection while preserving test injection hooks.
