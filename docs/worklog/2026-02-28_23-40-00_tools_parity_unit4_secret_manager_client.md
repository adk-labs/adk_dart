# Tools Parity Work Unit 4: SecretManagerClient

## Scope
- Target: `lib/src/tools/apihub_tool/clients/secret_client.dart`
- Goal: move from placeholder behavior to real runtime behavior with Python-like credential resolution order.

## Changes
- Implemented default Secret Manager fetch path (REST):
  - resolves bearer token
  - calls `GET https://secretmanager.googleapis.com/v1/{resource}:access`
  - decodes `payload.data` base64 to UTF-8 secret value
- Added async credential resolution order:
  - explicit `authToken`
  - `serviceAccountJson` embedded token (`access_token`/`token`)
  - service account JWT exchange via `googleapis_auth`
  - default credentials fallback via `resolveDefaultGoogleAccessToken`
- Kept existing injectable fetcher hook (`setSecretManagerSecretFetcher`) for tests/custom integration.
- Added `googleapis_auth` dependency in `pubspec.yaml`.

## Tests
- Updated `test/apihub_tool_parity_test.dart`:
  - service account token extraction path
  - precedence of explicit `authToken` over service account embedded token
- Existing APIHub and SecretManager parity tests remain green.

## Validation
- Command:
  - `dart test test/apihub_tool_parity_test.dart`
- Result:
  - All tests passed.

## Notes
- Constructor still validates malformed JSON immediately.
- Runtime token exchange for service account key JSON now works without requiring custom fetcher injection.
