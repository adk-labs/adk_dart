# ADK Dart Examples

ADK (Agent Development Kit) Dart 패키지를 사용하여 AI 에이전트를 개발하고 활용하는 다양한 단계별 예제 프로젝트 모음입니다.

각 예제는 사용자가 쉽게 다운로드하여 단독 프로젝트로 컴파일 및 동작시킬 수 있는 완성형 **Dart CLI 프로젝트** 형태로 구성되어 있습니다.

## 예제 목록

1. **[01_echo_agent](./01_echo_agent)**
   - **설명**: 에이전트 개발의 가장 핵심적인 기초 구성법을 다룹니다. 커스텀 LLM(`BaseLlm`)을 상속받아 에이전트와 Runner를 생성하고 로컬 세션을 통해 간단한 에코 대화를 수행합니다.
   
2. **[02_weather_agent](./02_weather_agent)**
   - **설명**: 에이전트에게 외부 날씨 검색을 위한 Dart 함수(`FunctionTool`)를 바인딩하고, 모델이 필요에 따라 자동으로 해당 함수를 호출하는 **도구 사용(Tool Calling)**의 흐름을 보여줍니다.

3. **[03_multi_agent_search](./03_multi_agent_search)**
   - **설명**: 여러 에이전트 간에 대화 맥락과 실행 권한을 전환하는 **Hand-off 오케스트레이션**과 실제 구글 검색 도구(`googleSearch`)를 연동하여 최신 웹 정보를 조회하는 법을 학습합니다.

4. **[04_local_environment](./04_local_environment)**
   - **설명**: 에이전트가 로컬 머신의 파일 시스템 및 터미널 명령어 실행 권한을 가지는 **실행 환경 연동(LocalEnvironment)** 구성 요소를 적용하는 예제입니다.

## 빠른 시작
각 하위 예제 폴더로 이동하여 의존성을 받고 바로 실행할 수 있습니다.

```bash
cd 01_echo_agent
dart pub get
dart run bin/main.dart
```

> [!IMPORTANT]
> 실제 LLM 기능 및 구글 검색이 연동되는 예제(`02`, `03`, `04`)의 경우 실행 전 시스템 환경 변수로 `GEMINI_API_KEY`를 설정해야 합니다.
> ```bash
> export GEMINI_API_KEY="your-gemini-api-key"
> ```
