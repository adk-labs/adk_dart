# ADK Go Daily Change Report

- Date (UTC): 2026-10-26
- Source: `google/adk-go`
- Latest SHA: `219c13059ecf654b7318d5927a607779711943e0`
- Previous SHA: `733b52570555653a768134ab827e01691be8d871`

## Summary

- New commits: 5

## Commits

- [219c130](https://github.com/google/adk-go/commit/219c13059ecf654b7318d5927a607779711943e0) fix(llmagent): save output_key when a before-agent callback short-circuits (#1963) (Anzal Husain Abidi, 2026-10-26)
- [6ede178](https://github.com/google/adk-go/commit/6ede178570c6ee708733f37d6b43663bfbd19537) fix(agentanalytics): pause stalled run-end uploads across batches (#1947) (ktsoator, 2026-10-26)
- [c43259a](https://github.com/google/adk-go/commit/c43259a11de2ad639d6c919ca58431a7b2088d9f) fix(session/vertexai): persist live transcriptions (#1964) (DisturbedCrow, 2026-10-26)
- [3fe0032](https://github.com/google/adk-go/commit/3fe0032bf87e8b14738983252d4d3e4ed66f1b71) fix(agentanalytics): log a deferred GCS retry only when it is requeued (#1941) (leilei3167, 2026-10-26)
- [45787ba](https://github.com/google/adk-go/commit/45787ba63bfa5b59a0ea84141e08e40a5fd80bb9) chore(deps): bump the go-minor-patch group with 3 updates (#1969) (dependabot[bot], 2026-10-26)

## Changed Files

- `M	agent/agent.go`
- `M	agent/llmagent/llmagent.go`
- `A	agent/llmagent/llmagent_beforecallback_outputkey_test.go`
- `M	go.mod`
- `M	go.sum`
- `M	internal/agent/state.go`
- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/config.go`
- `M	plugin/agentanalytics/gcs_offloader.go`
- `M	plugin/agentanalytics/gcs_offloader_test.go`
- `M	session/vertexai/raw_event_crossruntime_test.go`
- `M	session/vertexai/vertexai_client.go`
- `M	session/vertexai/vertexai_test.go`
