/// Platform helpers for abstracting unique ID generation.
library;

import 'dart:math';

typedef IdProvider = String Function();

final Random _random = Random();

String _defaultIdProvider() {
  final List<int> bytes = List<int>.generate(
    16,
    (_) => _random.nextInt(256),
    growable: false,
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String toHex(int value) => value.toRadixString(16).padLeft(2, '0');
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < bytes.length; index++) {
    buffer.write(toHex(bytes[index]));
    if (index == 3 || index == 5 || index == 7 || index == 9) {
      buffer.write('-');
    }
  }
  return buffer.toString();
}

IdProvider _idProvider = _defaultIdProvider;

/// Sets the provider used by [newUuid].
void setIdProvider(IdProvider provider) {
  _idProvider = provider;
}

/// Restores the default unique ID provider.
void resetIdProvider() {
  _idProvider = _defaultIdProvider;
}

/// Returns a new unique identifier string.
String newUuid() => _idProvider();
