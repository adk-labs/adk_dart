# flutter_adk 멀티플랫폼 플러그인 체크리스트

## 문서 목적
- `packages/flutter_adk`를 Android, iOS, Web, Linux, macOS, Windows에서 동작 가능한 Flutter 플러그인으로 도입한다.
- 기존 `adk_dart` 공개 API의 플랫폼 결합(`dart:io`, CLI 포함)을 분리해 Flutter/Web 컴파일 가능 경로를 확보한다.

## 현재 상태 요약
- [x] `adk_dart` 메인 엔트리(`lib/adk_dart.dart`)가 광범위한 모듈을 export 중
- [x] 다수 모듈이 `dart:io`에 직접 의존
- [x] facade 패키지 `packages/adk`가 `adk_dart`를 그대로 재export
- [ ] Flutter/Web-safe 전용 엔트리(`adk_core`) 없음
- [ ] `packages/flutter_adk` 패키지 없음

## 목표 범위
- [ ] `flutter_adk` 패키지 생성 및 6개 플랫폼 등록
- [ ] Flutter/Web-safe 공개 API 경로 확정 (`adk_core` 기반)
- [ ] Flutter용 기본 facade + 런타임 부트스트랩 제공
- [ ] 최소 스모크 테스트(웹 + 1개 이상 네이티브) 자동화
- [ ] CI에 Flutter 검사 단계 추가

## 비범위(초기 릴리스)
- [ ] CLI 기능(`adk run`, `adk web`, 배포/컨포먼스 도구) Flutter 노출
- [ ] 로컬 프로세스 실행 기반 코드 실행기(컨테이너/GKE/로컬 쉘) 완전 지원
- [ ] 모든 기존 `adk_dart` 기능의 Web parity 즉시 보장

## 단계별 체크리스트

### Phase 1: API 분리 (adk_dart)
- [ ] `lib/adk_core.dart` 생성 (Flutter/Web-safe export만 포함)
- [ ] IO/CLI 결합 API를 별도 경로로 유지 (`adk_dart.dart` 또는 `adk_io.dart`)
- [ ] `dart:io` 직접 참조 유틸 중 대체 가능한 항목은 인터페이스로 추상화
- [ ] 최소 컴파일 기준 수립: `adk_core` import 시 Flutter Web 컴파일 가능
- [ ] 문서화: 어떤 기능이 core에 포함/제외되는지 표로 정리

완료 기준(DoD)
- [ ] `adk_core`만 사용하는 샘플이 Flutter Web에서 빌드 성공
- [ ] 기존 VM/CLI 사용자는 breaking change 없이 유지

### Phase 2: flutter_adk 스캐폴드
- [ ] `packages/flutter_adk` 생성 (`flutter create --template=plugin --platforms=android,ios,web,linux,macos,windows`)
- [ ] 패키지 메타데이터 정리 (name: `flutter_adk`, description, repository, issue tracker)
- [ ] `pubspec.yaml`에 `flutter` SDK 및 `adk_dart` 의존 연결
- [ ] 예제 앱(`example/`)에서 기본 에이전트 실행 샘플 추가
- [ ] 패키지 엔트리(`lib/flutter_adk.dart`)와 내부 구조(`src/`) 정리

완료 기준(DoD)
- [ ] `flutter analyze` 통과
- [ ] example 앱 실행으로 기본 호출 경로 확인

### Phase 3: 플랫폼 어댑터 도입
- [ ] 인증/토큰 저장 인터페이스 정의 (secure storage adapter)
- [ ] 세션/상태 저장 기본 전략 정의 (초기: in-memory, 확장 포인트 제공)
- [ ] Web 제약 기능에 대해 graceful fallback 또는 명시적 Unsupported 처리
- [ ] 앱/디바이스 메타 주입 경로 정리 (필요 시 플러그인 채널)
- [ ] 에러 메시지 표준화 (플랫폼별 미지원 기능 안내)

완료 기준(DoD)
- [ ] 동일 API 호출이 6개 플랫폼에서 컴파일 가능
- [ ] 미지원 기능은 런타임에서 예측 가능한 에러로 처리

### Phase 4: 테스트 및 CI
- [ ] 단위 테스트: core facade, adapter fallback, 에러 시나리오
- [ ] 통합 스모크 테스트: Web + Android(또는 iOS) 최소 1개 네이티브
- [ ] GitHub Actions에 Flutter 단계 추가 (`flutter pub get`, `flutter analyze`, `flutter test`)
- [ ] 기존 `package-sync` 스크립트/정책을 `flutter_adk` 포함하도록 확장
- [ ] 릴리스 체크리스트 추가 (버전 동기화, changelog, publish 순서)

완료 기준(DoD)
- [ ] PR CI 녹색
- [ ] 배포 전 체크리스트 항목 100% 완료

## PR 분할 계획
- [ ] PR-1: `adk_core` 분리 + 최소 컴파일 검증
- [ ] PR-2: `packages/flutter_adk` 스캐폴드 + 기본 facade + example
- [ ] PR-3: 플랫폼 어댑터 + fallback 정책 + 테스트
- [ ] PR-4: CI/릴리스 자동화 및 문서 마무리

## 리스크 체크리스트
- [ ] `adk_dart.dart` 공개 API 변경에 따른 기존 사용자 영향 검토
- [ ] `dart:io` 의존 코드가 간접 참조로 남아 Web 빌드 실패하는지 검증
- [ ] 플랫폼별 저장소 구현 차이(secure storage/indexeddb/file) 정합성 검증
- [ ] Flutter 버전/다트 SDK 제약 충돌 여부 확인

## 의사결정 포인트
- [ ] `adk_dart.dart`를 기존처럼 VM 중심으로 유지할지, core 중심으로 재정의할지 결정
- [ ] 초기 persistent storage를 어떤 백엔드로 통일할지 결정
- [ ] Web에서 제외할 기능 목록 확정 및 문서 공개 범위 결정

## 착수 순서 (권장)
- [ ] 1순위: Phase 1 (API 분리)
- [ ] 2순위: Phase 2 (flutter_adk 생성)
- [ ] 3순위: Phase 3 (어댑터/폴백)
- [ ] 4순위: Phase 4 (CI/릴리스)
