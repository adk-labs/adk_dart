# Agent Development Kit (ADK) for Dart (`adk`)

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

`adk` は `adk_dart` を短い import 名で再公開するファサードパッケージです。

## 役割

- Short import: `package:adk/adk.dart`
- `adk_dart` API re-export
- `adk` CLI entrypoint

## `adk` を使うべきケース

`adk` を選ぶとよい場合:

- Dart VM/CLI 環境で短い import（`package:adk/adk.dart`）を使いたい
- `adk_dart` と同じ挙動を保ったままパッケージ名を短くしたい

別パッケージを選ぶ場合:

- Flutter アプリコード（特に Web 対応）: `flutter_adk`
- コア名を明示して使いたい: `adk_dart`

Design intent:

- `adk` はランタイム分岐のためではなく、命名/使い勝手のための
  ファサードです。
- つまり `adk_dart` と同じ VM 中心ランタイムを、より短い import 名で
  使いたいときの選択肢です。

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partial / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | Y | Partial | N | Re-exports the full `adk_dart` surface |
| `adk` CLI executable | Y | N | N | VM/terminal only |
| Runtime/tool features through facade | Y | Partial | N | Constraints are inherited from `adk_dart` |
| Dedicated web-safe entrypoint in this package | N | N | N | Use `adk_dart/adk_core.dart` or `flutter_adk` |

## Install

```bash
dart pub add adk
```

## Links

- Full details: [README.md](README.md)
- Core package: <https://pub.dev/packages/adk_dart>
