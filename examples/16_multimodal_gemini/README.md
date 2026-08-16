# 16. Multimodal Agent (Vision & Audio)

Demonstrates ingesting heterogeneous multimodal token streams (binary image bytes, audio buffers, MIME payloads) alongside text prompts using `InlineData` and `Part(inlineData: ...)`.

## Execution

```bash
cd examples/16_multimodal_gemini
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`InlineData` 및 `Part`를 활용하여 Base64/Raw 바이너리 이미지 바이트 및 오디오 스트림을 텍스트 토큰과 함께 멀티모달 텐서 입력으로 모델에 주입하여 시각 추론을 수행하는 예제입니다.

### 日本語
`InlineData` および `Part` を使用して、Base64/Raw バイナリ画像バイトや音声ストリームをテキストトークンと共にマルチモーダルテンソル入力としてモデルに注入し、視覚推論を実行するサンプルです。

### 中文
利用 `InlineData` 与 `Part` 将 Base64/Raw 二进制图像字节及音频流与文本 Token 一同作为多模态张量输入注入模型，以执行视觉推理的示例。
