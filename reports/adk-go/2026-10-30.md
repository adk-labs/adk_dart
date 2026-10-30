# ADK Go Daily Change Report

- Date (UTC): 2026-10-30
- Source: `google/adk-go`
- Latest SHA: `beea418caa2b5cc9417251a37e7ee527ae7f99df`
- Previous SHA: `714d35ffcef5e6652e14309d43b3e88a7ed0b956`

## Summary

- New commits: 6

## Commits

- [beea418](https://github.com/google/adk-go/commit/beea418caa2b5cc9417251a37e7ee527ae7f99df) feat(toolauth): add adk-python's auth data model and wire format (#2032) (Sasha, 2026-10-30)
- [c7b32cb](https://github.com/google/adk-go/commit/c7b32cba7d696af806f11d40b2152e1a7b07eaed) feat(exp): add LLMClassifier backed by model.LLM (#2035) (Rafal Glowinski, 2026-10-30)
- [1454362](https://github.com/google/adk-go/commit/1454362458e30e1d09541d24068e4c31b1420682) feat(exp): add workflow routing Node for classifiers (#2005) (Rafal Glowinski, 2026-10-30)
- [410c1ef](https://github.com/google/adk-go/commit/410c1ef96509a0548e394798fa3e54d8d3305584) Added google_maps, url_contex + gemini guards (#2026) (Karol Droste, 2026-10-30)
- [5f5e1b5](https://github.com/google/adk-go/commit/5f5e1b537e5e2932f0e97bd6606ece9020828029) feat(exp): add classifier interface and TypeSafe Jev decision model client (#2003) (Rafal Glowinski, 2026-10-30)
- [391b925](https://github.com/google/adk-go/commit/391b92529d107ec03c82b23fbbe60994f99530e4) fix(mcptoolset): give each user its own MCP session with Config.Auth (#1755) (Gangavarapu Vivek, 2026-10-30)

## Changed Files

- `M	auth/gcp/provider.go`
- `A	exp/classifier/classifier.go`
- `A	exp/classifier/classifier_test.go`
- `A	exp/classifier/doc.go`
- `A	exp/classifier/llm.go`
- `A	exp/classifier/llm_test.go`
- `A	exp/classifier/node.go`
- `A	exp/classifier/node_test.go`
- `A	exp/classifier/typesafe/doc.go`
- `A	exp/classifier/typesafe/errors.go`
- `A	exp/classifier/typesafe/typesafe.go`
- `A	exp/classifier/typesafe/typesafe_test.go`
- `M	exp/doc.go`
- `M	internal/llminternal/basic_processor.go`
- `M	internal/llminternal/googlellm/variant.go`
- `M	internal/llminternal/googlellm/variant_test.go`
- `A	internal/workflowroute/workflowroute.go`
- `A	internal/workflowroute/workflowroute_test.go`
- `A	tool/geminitool/enterprise_web_search.go`
- `A	tool/geminitool/enterprise_web_search_test.go`
- `A	tool/geminitool/google_maps.go`
- `M	tool/geminitool/google_search.go`
- `M	tool/geminitool/tool.go`
- `A	tool/geminitool/url_context.go`
- `A	tool/mcptoolset/auth_session_test.go`
- `M	tool/mcptoolset/client.go`
- `M	tool/mcptoolset/client_test.go`
- `A	tool/mcptoolset/export_test.go`
- `M	tool/mcptoolset/set.go`
- `A	tool/toolauth/auth_credential.go`
- `A	tool/toolauth/auth_credential_test.go`
- `A	tool/toolauth/auth_schemes.go`
- `A	tool/toolauth/auth_schemes_test.go`
- `A	tool/toolauth/auth_tool.go`
- `A	tool/toolauth/auth_tool_test.go`
- `A	tool/toolauth/doc.go`
- `A	tool/toolauth/model_json.go`
- `A	tool/toolauth/redact.go`
- `A	tool/toolauth/redact_test.go`
- `M	workflow/validation.go`
- `M	workflow/validation_test.go`
