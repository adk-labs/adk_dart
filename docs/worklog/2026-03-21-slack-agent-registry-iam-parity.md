# March 18-19 Remaining Integration Parity

## Scope

Closed the remaining runtime-facing March 18-19 parity gaps against `ref/adk-python` in the user-requested order:

1. Slack integration
2. Agent Registry integration
3. GCP IAM connector auth surface

## Work Unit 1: Slack integration

### Applied
- Added adapter-based Slack runtime surface in `lib/src/integrations/slack/slack_runner.dart`.
- Registered `app_mention` and `message` handlers through `SlackAppAdapter`.
- Matched Python runner behavior for:
  - DM/thread filtering
  - `_Thinking..._` placeholder message
  - first text chunk via `chatUpdate`
  - follow-up text chunks via `say`
  - placeholder delete on empty result
  - error fallback update/message
- Added optional `socketModeHandlerFactory` so real socket mode startup can be wired without forcing a package dependency in `adk_dart` core.

### Verification
- `dart test test/slack_runner_test.dart`

## Work Unit 2: Agent Registry integration

### Applied
- Added REST + ADC backed Agent Registry client in `lib/src/integrations/agent_registry/agent_registry.dart`.
- Implemented:
  - `listMcpServers`
  - `getMcpServer`
  - `getMcpToolset`
  - `listAgents`
  - `getAgentInfo`
  - `getRemoteA2aAgent`
- Added connection URI resolution for top-level `interfaces` and nested `protocols`.
- Matched the 3/19 Python fix by preferring the stored full A2A agent card when `card.type == A2A_AGENT_CARD`.
- Normalized camelCase stored card payloads such as `defaultInputModes` / `defaultOutputModes` before constructing Dart `AgentCard`.

### Verification
- `dart test test/agent_registry_parity_test.dart`

## Work Unit 3: GCP IAM connector auth surface

### Applied
- Added `GcpIamConnectorAuth` in `lib/src/integrations/_iam_connectors/gcp_iam_connector_auth.dart`.
- Added noop `GcpAuthProvider` in `lib/src/integrations/_iam_connectors/gcp_auth_provider.dart`.
- Added feature flag `FeatureName.gcpIamConnectorAuth`, default off.
- Updated `CredentialManager` to auto-register the noop provider when the feature is enabled.
- Added registry and manager regression coverage for serialized IAM connector auth schemes.

### Verification
- `dart test test/auth_provider_registry_test.dart test/credential_manager_test.dart`

## Public Surface

Exported new integration modules from `lib/adk_dart.dart`:
- `src/integrations/slack/slack_runner.dart`
- `src/integrations/agent_registry/agent_registry.dart`
- `src/integrations/_iam_connectors/gcp_iam_connector_auth.dart`
- `src/integrations/_iam_connectors/gcp_auth_provider.dart`

## Full Validation

- `dart analyze lib/src/integrations/slack/slack_runner.dart lib/src/integrations/agent_registry/agent_registry.dart lib/src/integrations/_iam_connectors/gcp_auth_provider.dart lib/src/integrations/_iam_connectors/gcp_iam_connector_auth.dart lib/src/auth/credential_manager.dart lib/src/features/_feature_registry.dart lib/adk_dart.dart test/slack_runner_test.dart test/agent_registry_parity_test.dart test/auth_provider_registry_test.dart test/credential_manager_test.dart`
- `dart test test/slack_runner_test.dart test/agent_registry_parity_test.dart test/auth_provider_registry_test.dart test/credential_manager_test.dart`
