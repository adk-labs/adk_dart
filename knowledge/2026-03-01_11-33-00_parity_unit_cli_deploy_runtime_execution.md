# Parity Unit: `adk deploy` Runtime Execution

작성 시각: 2026-03-01 11:33:00

## 배경
- P0 항목 중 `adk deploy`가 실제 배포를 수행하지 않고 gcloud 명령만 출력하던 문제를 처리.

## 반영 내용
- 파일: `lib/src/cli/cli_deploy.dart`
  - 배포 실행 진입점 `runDeployCommand` 추가.
  - 옵션 파서 추가:
    - `--target` (`cloud_run|agent_engine|gke`)
    - `--project`, `--region`, `--service`, `--image`
    - `--dry-run`
    - `--` 이후 gcloud 추가 인자 전달
  - 기본 실행 경로 추가:
    - dry-run이 아니면 실제 `gcloud` 프로세스 실행.
    - stdout/stderr 스트리밍 전달.
- 파일: `lib/src/dev/cli.dart`
  - 최상위 `deploy` 커맨드를 실제 실행 경로로 연결.
  - usage 문구에 deploy 명령 반영.
- 파일: `lib/src/cli/cli_tools_click.dart`
  - 기존 preview-only 분기 제거, `runDeployCommand`로 위임.

## 테스트
- 파일: `test/cli_deploy_test.dart` (신규)
  - non-dry-run에서 runner 호출 검증.
  - dry-run 출력/runner 미호출 검증.
  - `agent_engine` 타겟 및 forwarded args 검증.
  - invalid target, missing project 에러 코드 검증.
- 파일: `test/cli_tools_click_parity_test.dart`
  - deploy 테스트를 `--dry-run` 기준으로 갱신.

## 검증
- `dart test test/cli_deploy_test.dart` : PASS
- `dart test test/cli_tools_click_parity_test.dart` : PASS
- `dart test test/dev_cli_test.dart` : PASS
- `dart analyze lib/src/cli/cli_deploy.dart lib/src/cli/cli_tools_click.dart lib/src/dev/cli.dart test/cli_deploy_test.dart test/cli_tools_click_parity_test.dart` : PASS

## 결과
- `adk deploy`가 기본값으로 실제 gcloud 실행 경로를 갖게 되었고, `--dry-run`으로 기존 preview 확인도 유지.
