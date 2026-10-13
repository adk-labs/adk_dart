# ADK Go Daily Change Report

- Date (UTC): 2026-10-13
- Source: `google/adk-go`
- Latest SHA: `5226417e7591bb75d680047b01578e0fa6078f09`
- Previous SHA: `40d37cad8feffd20f6790961a604789b9b5049ac`

## Summary

- New commits: 7

## Commits

- [5226417](https://github.com/google/adk-go/commit/5226417e7591bb75d680047b01578e0fa6078f09) fix(model/gemini): let the genai SDK resume paused generations (#1822) (João Westerberg, 2026-10-13)
- [cc4495a](https://github.com/google/adk-go/commit/cc4495a85242a96b458493929fc8e6d0fc6c5600) fix(server/triggers): let the Pub/Sub and Eventarc endpoints require a Google OIDC token (#1737) (wolo, 2026-10-13)
- [893687b](https://github.com/google/adk-go/commit/893687bfa24e032be0413c3fcd774caecc83694b) fix(runner): drop nil parts from live requests (#1795) (Trainingcqy, 2026-10-13)
- [a161b71](https://github.com/google/adk-go/commit/a161b7135de3c430f5290289052bf18f8868a438) docs(artifact): clarify missing-version deletion behavior (#1767) (ktsoator, 2026-10-13)
- [5381399](https://github.com/google/adk-go/commit/5381399b87b72859402db7a0d803953c699f7dd8) feat(auth): refresh and retry once on a downstream 401/403 (#1136) (wolo, 2026-10-13)
- [1064032](https://github.com/google/adk-go/commit/106403207c4c22471dc077fa8b380ba1bd836283) chore(version): bump the tagged version constant to 2.6.0 (#1817) (wolo, 2026-10-13)
- [5294837](https://github.com/google/adk-go/commit/52948375397a35dbd7896b832816401e063058eb) fix: reject Cloud Run service name beginning with '-' (#1505) (herdiyanitdev, 2026-10-13)

## Changed Files

- `M	artifact/gcsartifact/gcs_test.go`
- `M	artifact/service.go`
- `M	auth/credential.go`
- `M	auth/credential_test.go`
- `M	auth/gcp/agentidentity.go`
- `M	auth/gcp/client.go`
- `M	auth/gcp/client_test.go`
- `M	auth/gcp/connector.go`
- `M	auth/gcp/provider.go`
- `M	auth/gcp/provider_internal_test.go`
- `M	auth/gcp/provider_test.go`
- `M	auth/gcp/redact.go`
- `M	auth/providers.go`
- `M	auth/store.go`
- `M	auth/transport.go`
- `M	auth/transport_test.go`
- `M	cmd/adkgo/internal/deploy/cloudrun/cloudrun.go`
- `M	cmd/adkgo/internal/deploy/cloudrun/cloudrun_test.go`
- `M	cmd/launcher/web/triggers/eventarc/eventarc.go`
- `A	cmd/launcher/web/triggers/eventarc/eventarc_test.go`
- `A	cmd/launcher/web/triggers/internal/triggerauth/triggerauth.go`
- `A	cmd/launcher/web/triggers/internal/triggerauth/triggerauth_test.go`
- `M	cmd/launcher/web/triggers/pubsub/pubsub.go`
- `M	cmd/launcher/web/triggers/pubsub/pubsub_test.go`
- `M	go.mod`
- `M	go.sum`
- `M	internal/version/version.go`
- `D	model/gemini/continuation.go`
- `M	model/gemini/continuation_test.go`
- `M	model/gemini/gemini.go`
- `M	model/openaimodel/doc.go`
- `M	model/openaimodel/internal/responses/request_test.go`
- `M	runner/live_runner_test.go`
- `M	runner/runner.go`
