# flutter_adk_example

`flutter_adk` 챗봇 예제 앱입니다.

## 포함 기능
- 채팅 UI (사용자/어시스턴트 버블)
- 설정 시트에서 Gemini API 키 입력/저장
- `Agent + InMemoryRunner + Gemini + FunctionTool` 실행 경로
- 수도 조회 툴(`get_capital_city`) 포함

## 실행

```bash
flutter pub get
flutter run
```

웹 빌드:
```bash
flutter build web
```

## 주의사항
- 브라우저에 API 키를 저장하는 방식은 노출 위험이 있으므로 프로덕션에서는 서버 프록시를 권장합니다.
- 로컬 개발에서 최신 루트 소스를 참조하기 위해 `pubspec_overrides.yaml`이 포함되어 있습니다.
