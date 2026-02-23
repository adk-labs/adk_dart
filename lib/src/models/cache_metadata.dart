class CacheMetadata {
  CacheMetadata({
    this.cacheName,
    this.expireTime,
    required this.fingerprint,
    this.invocationsUsed,
    required this.contentsCount,
    this.createdAt,
  });

  final String? cacheName;
  final double? expireTime;
  final String fingerprint;
  final int? invocationsUsed;
  final int contentsCount;
  final double? createdAt;

  bool get expireSoon {
    final double? expiresAt = expireTime;
    if (expiresAt == null) {
      return false;
    }
    const double bufferSeconds = 120;
    final double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return now > (expiresAt - bufferSeconds);
  }

  CacheMetadata copyWith({
    Object? cacheName = _sentinel,
    Object? expireTime = _sentinel,
    String? fingerprint,
    Object? invocationsUsed = _sentinel,
    int? contentsCount,
    Object? createdAt = _sentinel,
  }) {
    return CacheMetadata(
      cacheName: identical(cacheName, _sentinel)
          ? this.cacheName
          : cacheName as String?,
      expireTime: identical(expireTime, _sentinel)
          ? this.expireTime
          : expireTime as double?,
      fingerprint: fingerprint ?? this.fingerprint,
      invocationsUsed: identical(invocationsUsed, _sentinel)
          ? this.invocationsUsed
          : invocationsUsed as int?,
      contentsCount: contentsCount ?? this.contentsCount,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as double?,
    );
  }

  @override
  String toString() {
    if (cacheName == null) {
      return 'Fingerprint-only: $contentsCount contents, '
          'fingerprint=${_shortFingerprint(fingerprint)}...';
    }

    final String cacheId = cacheName!.split('/').last;
    final double? expiresAt = expireTime;
    if (expiresAt == null) {
      return 'Cache $cacheId: used $invocationsUsed invocations, '
          'cached $contentsCount contents, expires unknown';
    }

    final double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final double mins = (expiresAt - now) / 60.0;
    return 'Cache $cacheId: used $invocationsUsed invocations, '
        'cached $contentsCount contents, expires in ${mins.toStringAsFixed(1)}m';
  }
}

String _shortFingerprint(String fingerprint) {
  if (fingerprint.length <= 8) {
    return fingerprint;
  }
  return fingerprint.substring(0, 8);
}

const Object _sentinel = Object();
