import 'dart:math';

final Random _random = Random();
const int _kUint32MaxExclusive = 0x100000000; // 2^32

String newAdkId({String prefix = ''}) {
  final int ts = DateTime.now().microsecondsSinceEpoch;
  final int nonce = _random.nextInt(_kUint32MaxExclusive);
  return '$prefix$ts$nonce';
}
