# ADK Go Daily Change Report

- Date (UTC): 2026-10-17
- Source: `google/adk-go`
- Latest SHA: `74faa9ab6bf58b47653ed275f4aa86a93e76280a`
- Previous SHA: `c7ed87daa909e7563d3167e57daedee55f557d91`

## Summary

- New commits: 2

## Commits

- [74faa9a](https://github.com/google/adk-go/commit/74faa9ab6bf58b47653ed275f4aa86a93e76280a) feat(model/openaimodel): support image/file input via genai InlineData/FileData parts (#1543) (Anton Dziatkovskii, 2026-10-16)
- [ec0c362](https://github.com/google/adk-go/commit/ec0c362bf00aaf649f0839517762f33ab65ee4d4) fix(mcptoolset): stop using context.Background() in connectionRefresher.Close (#1844) (wolo, 2026-10-17)

## Changed Files

- `M	model/openaimodel/errors.go`
- `A	model/openaimodel/internal/completions/media_test.go`
- `M	model/openaimodel/internal/completions/request.go`
- `M	model/openaimodel/internal/completions/request_test.go`
- `M	model/openaimodel/internal/responses/request.go`
- `M	model/openaimodel/internal/responses/request_test.go`
- `M	model/openaimodel/internal/shared/contents.go`
- `M	model/openaimodel/internal/shared/contents_test.go`
- `M	model/openaimodel/internal/shared/errors.go`
- `A	model/openaimodel/internal/shared/media.go`
- `A	model/openaimodel/internal/shared/media_test.go`
- `M	model/openaimodel/openaimodel_test.go`
- `M	tool/mcptoolset/client.go`
- `M	tool/mcptoolset/client_cancellation_test.go`
