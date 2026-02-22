import 'dart:math';

final Random _random = Random();

String newAdkId({String prefix = ''}) {
  final int ts = DateTime.now().microsecondsSinceEpoch;
  final int nonce = _random.nextInt(1 << 32);
  return '$prefix$ts$nonce';
}
