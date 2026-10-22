/// Cloud KMS envelope encryption utilities and credential wrappers.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Maximum number of entries retained in each KMS DEK/cipher cache.
const int maxKmsCacheSize = 1024;

/// Prefix prepended to KMS-encrypted credential fields in serialized JSON.
const String kmsCiphertextPrefix = 'kms:';

/// Credential field names subject to KMS envelope encryption.
const List<String> kmsEncryptedCredentialFields = <String>[
  'token',
  'refresh_token',
  'client_secret',
  'rapt_token',
];

/// Contract for wrapping and unwrapping Data Encryption Keys (DEKs) with KMS.
abstract class KmsClient {
  /// Creates a KMS client.
  const KmsClient();

  /// Encrypts [plaintext] using the Cloud KMS key identified by [keyName].
  Uint8List encrypt({required String keyName, required Uint8List plaintext});

  /// Decrypts [ciphertext] using the Cloud KMS key identified by [keyName].
  Uint8List decrypt({required String keyName, required Uint8List ciphertext});
}

/// Callback signature for KMS encryption operations.
typedef KmsEncryptCallback =
    Uint8List Function({required String keyName, required Uint8List plaintext});

/// Callback signature for KMS decryption operations.
typedef KmsDecryptCallback =
    Uint8List Function({
      required String keyName,
      required Uint8List ciphertext,
    });

/// [KmsClient] implementation backed by injectable encrypt/decrypt callbacks.
class CallbackKmsClient extends KmsClient {
  /// Creates a callback-backed KMS client.
  const CallbackKmsClient({
    required KmsEncryptCallback onEncrypt,
    required KmsDecryptCallback onDecrypt,
  }) : _onEncrypt = onEncrypt,
       _onDecrypt = onDecrypt;

  final KmsEncryptCallback _onEncrypt;
  final KmsDecryptCallback _onDecrypt;

  @override
  Uint8List encrypt({required String keyName, required Uint8List plaintext}) {
    return _onEncrypt(keyName: keyName, plaintext: plaintext);
  }

  @override
  Uint8List decrypt({required String keyName, required Uint8List ciphertext}) {
    return _onDecrypt(keyName: keyName, ciphertext: ciphertext);
  }
}

/// Deterministic local envelope [KmsClient] used when no external KMS client is injected.
///
/// Binds wrapped DEKs to the canonical KMS key resource path (excluding
/// `/cryptoKeyVersions/...` suffixes) using authenticated encryption so unit
/// tests can exercise full round-trip encryption and key-mismatch detection
/// without requiring live Google Cloud credentials.
class LocalKmsClient extends KmsClient {
  /// Creates a local KMS client with an optional [masterSecret].
  const LocalKmsClient({this.masterSecret = 'adk_local_kms_master_secret'});

  /// Master secret mixed with the normalized KMS key resource name.
  final String masterSecret;

  String _canonicalKeyResource(String keyName) {
    return keyName.split('/cryptoKeyVersions/').first;
  }

  Uint8List _deriveKek(String keyName) {
    final String resource = _canonicalKeyResource(keyName);
    final Hmac hmac = Hmac(sha256, utf8.encode(masterSecret));
    return Uint8List.fromList(hmac.convert(utf8.encode(resource)).bytes);
  }

  @override
  Uint8List encrypt({required String keyName, required Uint8List plaintext}) {
    final Uint8List kek = _deriveKek(keyName);
    return _SymmetricEnvelopeCipher(kek).encryptBytes(plaintext);
  }

  @override
  Uint8List decrypt({required String keyName, required Uint8List ciphertext}) {
    final Uint8List kek = _deriveKek(keyName);
    return _SymmetricEnvelopeCipher(kek).decryptBytes(ciphertext);
  }
}

class _SymmetricEnvelopeCipher {
  _SymmetricEnvelopeCipher(Uint8List key)
    : _encKey = Uint8List.fromList(
        Hmac(sha256, key).convert(utf8.encode('enc')).bytes,
      ),
      _macKey = Uint8List.fromList(
        Hmac(sha256, key).convert(utf8.encode('mac')).bytes,
      );

  final Uint8List _encKey;
  final Uint8List _macKey;

  static final Random _random = _createRandom();

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static Uint8List randomBytes(int length) {
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  Uint8List _keystream(Uint8List nonce, int length) {
    final Uint8List stream = Uint8List(length);
    int offset = 0;
    int counter = 0;
    while (offset < length) {
      final ByteData counterBytes = ByteData(4)..setUint32(0, counter);
      final List<int> input = <int>[
        ...nonce,
        ...counterBytes.buffer.asUint8List(),
      ];
      final List<int> block = Hmac(sha256, _encKey).convert(input).bytes;
      final int take = min(block.length, length - offset);
      stream.setRange(offset, offset + take, block);
      offset += take;
      counter += 1;
    }
    return stream;
  }

  Uint8List encryptBytes(Uint8List plaintext) {
    final Uint8List nonce = randomBytes(16);
    final Uint8List stream = _keystream(nonce, plaintext.length);
    final Uint8List body = Uint8List(plaintext.length);
    for (int i = 0; i < plaintext.length; i++) {
      body[i] = plaintext[i] ^ stream[i];
    }
    final List<int> macInput = <int>[...nonce, ...body];
    final List<int> tag = Hmac(sha256, _macKey).convert(macInput).bytes;
    return Uint8List.fromList(<int>[...nonce, ...tag, ...body]);
  }

  Uint8List decryptBytes(Uint8List token) {
    if (token.length < 48) {
      throw ArgumentError('Invalid or corrupted ciphertext token.');
    }
    final Uint8List nonce = token.sublist(0, 16);
    final Uint8List expectedTag = token.sublist(16, 48);
    final Uint8List body = token.sublist(48);
    final List<int> actualTag = Hmac(
      sha256,
      _macKey,
    ).convert(<int>[...nonce, ...body]).bytes;

    int diff = 0;
    for (int i = 0; i < 32; i++) {
      diff |= expectedTag[i] ^ actualTag[i];
    }
    if (diff != 0) {
      throw ArgumentError('Ciphertext authentication failed.');
    }

    final Uint8List stream = _keystream(nonce, body.length);
    final Uint8List plaintext = Uint8List(body.length);
    for (int i = 0; i < body.length; i++) {
      plaintext[i] = body[i] ^ stream[i];
    }
    return plaintext;
  }

  String encryptString(String value) {
    final Uint8List encrypted = encryptBytes(
      Uint8List.fromList(utf8.encode(value)),
    );
    return base64Url.encode(encrypted);
  }

  String decryptString(String encoded) {
    final Uint8List raw;
    try {
      raw = base64Url.decode(base64Url.normalize(encoded));
    } catch (_) {
      throw ArgumentError('Invalid base64 ciphertext.');
    }
    final Uint8List decrypted = decryptBytes(raw);
    return utf8.decode(decrypted);
  }
}

final LinkedHashMap<String, (Uint8List, String)> _kmsKeyDekCache =
    LinkedHashMap<String, (Uint8List, String)>();
final LinkedHashMap<(String, String), _SymmetricEnvelopeCipher> _dekCipherCache =
    LinkedHashMap<(String, String), _SymmetricEnvelopeCipher>();
final LinkedHashMap<String, KmsClient> _kmsClientCache =
    LinkedHashMap<String, KmsClient>();

KmsClient Function()? _kmsClientFactory;

/// Overrides the default [KmsClient] factory used by [encryptCredentials] and
/// [decryptCredentials], and clears cached KMS clients.
void setDefaultKmsClientFactory(KmsClient Function()? factory) {
  _kmsClientFactory = factory;
  _kmsClientCache.clear();
}

/// Clears all internal KMS DEK, cipher, and client caches.
void clearKmsCaches() {
  _kmsKeyDekCache.clear();
  _dekCipherCache.clear();
  _kmsClientCache.clear();
}

void _putBounded<K, V>(LinkedHashMap<K, V> cache, K key, V value) {
  if (cache.containsKey(key)) {
    cache.remove(key);
  } else if (cache.length >= maxKmsCacheSize) {
    cache.remove(cache.keys.first);
  }
  cache[key] = value;
}

V? _getLru<K, V>(LinkedHashMap<K, V> cache, K key) {
  final V? value = cache.remove(key);
  if (value != null) {
    cache[key] = value;
  }
  return value;
}

KmsClient _getKmsClient([KmsClient? override]) {
  if (override != null) {
    return override;
  }
  final KmsClient? cached = _getLru(_kmsClientCache, 'default');
  if (cached != null) {
    return cached;
  }
  final KmsClient created = _kmsClientFactory != null
      ? _kmsClientFactory!()
      : const LocalKmsClient();
  _putBounded(_kmsClientCache, 'default', created);
  return created;
}

(Uint8List, String) _getOrCreateDek(String kmsKeyName, [KmsClient? kmsClient]) {
  if (kmsClient == null) {
    final (Uint8List, String)? cached = _getLru(_kmsKeyDekCache, kmsKeyName);
    if (cached != null) {
      return cached;
    }
  }

  final Uint8List dek = _SymmetricEnvelopeCipher.randomBytes(32);
  final KmsClient client = _getKmsClient(kmsClient);
  final Uint8List encryptedDek = client.encrypt(
    keyName: kmsKeyName,
    plaintext: dek,
  );
  final String wrappedDekB64 = base64Encode(encryptedDek);
  final (Uint8List, String) result = (dek, wrappedDekB64);

  if (kmsClient == null) {
    _putBounded(_kmsKeyDekCache, kmsKeyName, result);
  }
  return result;
}

_SymmetricEnvelopeCipher _getCipherFromWrappedDek(
  String kmsKeyName,
  String wrappedDekB64, [
  KmsClient? kmsClient,
]) {
  final (String, String) cacheKey = (kmsKeyName, wrappedDekB64);
  if (kmsClient == null) {
    final _SymmetricEnvelopeCipher? cached = _getLru(_dekCipherCache, cacheKey);
    if (cached != null) {
      return cached;
    }
  }

  final KmsClient client = _getKmsClient(kmsClient);
  final Uint8List ciphertext = base64Decode(wrappedDekB64);
  final Uint8List dek = client.decrypt(
    keyName: kmsKeyName,
    ciphertext: ciphertext,
  );
  final _SymmetricEnvelopeCipher cipher = _SymmetricEnvelopeCipher(dek);

  if (kmsClient == null) {
    _putBounded(_dekCipherCache, cacheKey, cipher);
  }
  return cipher;
}

/// Result returned by [encryptCredentials].
class EncryptedCredentialsResult {
  /// Creates an encrypted credentials result.
  const EncryptedCredentialsResult({
    required this.encryptedToken,
    required this.encryptedRefreshToken,
    required this.encryptedClientSecret,
    required this.encryptedRaptToken,
    required this.wrappedDek,
  });

  /// Encrypted OAuth access token, or `null` if none was provided.
  final String? encryptedToken;

  /// Encrypted OAuth refresh token, or `null` if none was provided.
  final String? encryptedRefreshToken;

  /// Encrypted OAuth client secret, or `null` if none was provided.
  final String? encryptedClientSecret;

  /// Encrypted RAPT token, or `null` if none was provided.
  final String? encryptedRaptToken;

  /// Base64-encoded KMS-wrapped Data Encryption Key (DEK).
  final String? wrappedDek;

  /// Returns the 5-tuple elements in positional order.
  List<String?> toList() => <String?>[
    encryptedToken,
    encryptedRefreshToken,
    encryptedClientSecret,
    encryptedRaptToken,
    wrappedDek,
  ];

  /// Accesses tuple elements by index (`0..4`).
  String? operator [](int index) => toList()[index];
}

/// Result returned by [decryptCredentials].
class DecryptedCredentialsResult {
  /// Creates a decrypted credentials result.
  const DecryptedCredentialsResult({
    required this.token,
    required this.refreshToken,
    required this.clientSecret,
    required this.raptToken,
  });

  /// Decrypted OAuth access token, or `null` if none was provided.
  final String? token;

  /// Decrypted OAuth refresh token, or `null` if none was provided.
  final String? refreshToken;

  /// Decrypted OAuth client secret, or `null` if none was provided.
  final String? clientSecret;

  /// Decrypted RAPT token, or `null` if none was provided.
  final String? raptToken;

  /// Returns the 4-tuple elements in positional order.
  List<String?> toList() => <String?>[
    token,
    refreshToken,
    clientSecret,
    raptToken,
  ];

  /// Accesses tuple elements by index (`0..3`).
  String? operator [](int index) => toList()[index];
}

/// Encrypts sensitive credential strings using envelope encryption with KMS.
EncryptedCredentialsResult encryptCredentials({
  required String kmsKeyName,
  String? token,
  String? refreshToken,
  String? clientSecret,
  String? raptToken,
  KmsClient? kmsClient,
}) {
  if (token == null &&
      refreshToken == null &&
      clientSecret == null &&
      raptToken == null) {
    return const EncryptedCredentialsResult(
      encryptedToken: null,
      encryptedRefreshToken: null,
      encryptedClientSecret: null,
      encryptedRaptToken: null,
      wrappedDek: null,
    );
  }

  final (Uint8List dek, String wrappedDek) = _getOrCreateDek(
    kmsKeyName,
    kmsClient,
  );
  final _SymmetricEnvelopeCipher cipher = _SymmetricEnvelopeCipher(dek);

  String? encryptStr(String? value) {
    if (value == null) {
      return null;
    }
    return cipher.encryptString(value);
  }

  return EncryptedCredentialsResult(
    encryptedToken: encryptStr(token),
    encryptedRefreshToken: encryptStr(refreshToken),
    encryptedClientSecret: encryptStr(clientSecret),
    encryptedRaptToken: encryptStr(raptToken),
    wrappedDek: wrappedDek,
  );
}

/// Decrypts sensitive credential strings using the KMS-wrapped DEK.
DecryptedCredentialsResult decryptCredentials({
  required String kmsKeyName,
  String? encryptedToken,
  String? encryptedRefreshToken,
  String? encryptedClientSecret,
  String? encryptedRaptToken,
  String? wrappedDek,
  KmsClient? kmsClient,
}) {
  if (encryptedToken == null &&
      encryptedRefreshToken == null &&
      encryptedClientSecret == null &&
      encryptedRaptToken == null) {
    return DecryptedCredentialsResult(
      token: encryptedToken,
      refreshToken: encryptedRefreshToken,
      clientSecret: encryptedClientSecret,
      raptToken: encryptedRaptToken,
    );
  }

  if (wrappedDek == null || wrappedDek.isEmpty) {
    throw ArgumentError(
      'Encrypted credential fields were provided, but wrapped_dek is missing; cannot decrypt credentials.',
    );
  }

  final _SymmetricEnvelopeCipher cipher = _getCipherFromWrappedDek(
    kmsKeyName,
    wrappedDek,
    kmsClient,
  );

  String? decryptStr(String? value) {
    if (value == null) {
      return null;
    }
    return cipher.decryptString(value);
  }

  return DecryptedCredentialsResult(
    token: decryptStr(encryptedToken),
    refreshToken: decryptStr(encryptedRefreshToken),
    clientSecret: decryptStr(encryptedClientSecret),
    raptToken: decryptStr(encryptedRaptToken),
  );
}

/// Envelope encryptor bound to a specific Cloud KMS key and optional [KmsClient].
///
/// ```dart
/// final encryptor = KmsEncryptor(
///   kmsKeyName: 'projects/my-proj/locations/us/keyRings/ring/cryptoKeys/key',
/// );
/// final encrypted = encryptor.encrypt( token: 'ya29.secret');
/// final decrypted = encryptor.decrypt(
///   encryptedToken: encrypted.encryptedToken,
///   wrappedDek: encrypted.wrappedDek,
/// );
/// ```
class KmsEncryptor {
  /// Creates a KMS envelope encryptor for [kmsKeyName].
  KmsEncryptor({
    required this.kmsKeyName,
    KmsClient? kmsClient,
    KmsEncryptCallback? onEncrypt,
    KmsDecryptCallback? onDecrypt,
  }) : kmsClient =
           kmsClient ??
           (onEncrypt != null && onDecrypt != null
               ? CallbackKmsClient(onEncrypt: onEncrypt, onDecrypt: onDecrypt)
               : null) {
    if (kmsKeyName.trim().isEmpty) {
      throw ArgumentError('kmsKeyName must not be empty.');
    }
  }

  /// Cloud KMS crypto key resource name.
  final String kmsKeyName;

  /// Optional custom KMS client used for DEK wrapping and unwrapping.
  final KmsClient? kmsClient;

  /// Encrypts the provided credential fields using this encryptor's KMS key.
  EncryptedCredentialsResult encrypt({
    String? token,
    String? refreshToken,
    String? clientSecret,
    String? raptToken,
  }) {
    return encryptCredentials(
      kmsKeyName: kmsKeyName,
      token: token,
      refreshToken: refreshToken,
      clientSecret: clientSecret,
      raptToken: raptToken,
      kmsClient: kmsClient,
    );
  }

  /// Decrypts the provided credential fields using [wrappedDek].
  DecryptedCredentialsResult decrypt({
    String? encryptedToken,
    String? encryptedRefreshToken,
    String? encryptedClientSecret,
    String? encryptedRaptToken,
    required String? wrappedDek,
  }) {
    return decryptCredentials(
      kmsKeyName: kmsKeyName.split('/cryptoKeyVersions/').first,
      encryptedToken: encryptedToken,
      encryptedRefreshToken: encryptedRefreshToken,
      encryptedClientSecret: encryptedClientSecret,
      encryptedRaptToken: encryptedRaptToken,
      wrappedDek: wrappedDek,
      kmsClient: kmsClient,
    );
  }
}

/// Google OAuth2 user credentials that support transparent Cloud KMS envelope
/// encryption when serialized to and from JSON.
///
/// ```dart
/// final creds = KmsEncryptedCredentials(
///   token: 'access-token-123',
///   refreshToken: 'refresh-token-456',
///   clientId: 'my-client-id',
///   clientSecret: 'my-client-secret',
///   kmsKeyName: 'projects/p/locations/l/keyRings/r/cryptoKeys/k',
/// );
/// final jsonStr = creds.toJson();
/// final restored = KmsEncryptedCredentials.fromAuthorizedUserInfo(
///   jsonDecode(jsonStr) as Map<String, Object?>,
/// );
/// ```
class KmsEncryptedCredentials {
  /// Creates KMS-aware OAuth2 credentials.
  KmsEncryptedCredentials({
    this.token,
    this.refreshToken,
    this.idToken,
    this.tokenUri,
    this.clientId,
    this.clientSecret,
    List<String>? scopes,
    List<String>? defaultScopes,
    this.quotaProjectId,
    this.expiry,
    this.raptToken,
    this.refreshHandler,
    this.enableReauthRefresh = false,
    List<String>? grantedScopes,
    this.universeDomain = 'googleapis.com',
    this.account,
    this.trustBoundary,
    this.kmsKeyName,
    this.wrappedDek,
    this.kmsClient,
  }) : scopes = scopes == null ? null : List<String>.unmodifiable(scopes),
       defaultScopes = defaultScopes == null
           ? null
           : List<String>.unmodifiable(defaultScopes),
       grantedScopes = grantedScopes == null
           ? null
           : List<String>.unmodifiable(grantedScopes);

  /// Creates [KmsEncryptedCredentials] from serialized authorized user [info].
  ///
  /// Automatically unwraps and decrypts `kms:`-prefixed credential fields when
  /// `kms_key_name` (or [kmsKeyName]) and `wrapped_dek` are present.
  factory KmsEncryptedCredentials.fromAuthorizedUserInfo(
    Map<String, Object?> info, {
    Iterable<String>? scopes,
    String? kmsKeyName,
    KmsClient? kmsClient,
  }) {
    final Map<String, Object?> infoCopy = Map<String, Object?>.from(info);
    final String? resolvedKmsKeyName =
        kmsKeyName ?? (infoCopy['kms_key_name'] as String?);
    final String? wrappedDek = infoCopy['wrapped_dek'] as String?;
    infoCopy.remove('kms_key_name');
    infoCopy.remove('wrapped_dek');

    if (resolvedKmsKeyName == null ||
        resolvedKmsKeyName.isEmpty ||
        wrappedDek == null ||
        wrappedDek.isEmpty) {
      for (final String field in kmsEncryptedCredentialFields) {
        final Object? val = infoCopy[field];
        if (val is String && val.startsWith(kmsCiphertextPrefix)) {
          throw ArgumentError(
            '$field is KMS-encrypted but no usable kms_key_name/wrapped_dek was found; cannot decrypt.',
          );
        }
      }
    } else {
      final Map<String, String?> encryptedFields = <String, String?>{};
      for (final String field in kmsEncryptedCredentialFields) {
        final Object? val = infoCopy[field];
        if (val is String && val.startsWith(kmsCiphertextPrefix)) {
          encryptedFields[field] = val.substring(kmsCiphertextPrefix.length);
        } else {
          encryptedFields[field] = null;
        }
      }

      if (encryptedFields.values.any((String? v) => v != null)) {
        final String kmsKeyForDecrypt = resolvedKmsKeyName
            .split('/cryptoKeyVersions/')
            .first;
        final DecryptedCredentialsResult decrypted = decryptCredentials(
          kmsKeyName: kmsKeyForDecrypt,
          encryptedToken: encryptedFields['token'],
          encryptedRefreshToken: encryptedFields['refresh_token'],
          encryptedClientSecret: encryptedFields['client_secret'],
          encryptedRaptToken: encryptedFields['rapt_token'],
          wrappedDek: wrappedDek,
          kmsClient: kmsClient,
        );
        if (encryptedFields['token'] != null) {
          infoCopy['token'] = decrypted.token;
        }
        if (encryptedFields['refresh_token'] != null) {
          infoCopy['refresh_token'] = decrypted.refreshToken;
        }
        if (encryptedFields['client_secret'] != null) {
          infoCopy['client_secret'] = decrypted.clientSecret;
        }
        if (encryptedFields['rapt_token'] != null) {
          infoCopy['rapt_token'] = decrypted.raptToken;
        }
      }
    }

    DateTime? parsedExpiry;
    final Object? rawExpiry = infoCopy['expiry'];
    if (rawExpiry is DateTime) {
      parsedExpiry = rawExpiry.toUtc();
    } else if (rawExpiry is String && rawExpiry.isNotEmpty) {
      final String normalized = rawExpiry.endsWith('Z')
          ? rawExpiry
          : '${rawExpiry}Z';
      parsedExpiry = DateTime.tryParse(normalized)?.toUtc();
    }

    List<String>? parseStringList(Object? value) {
      if (value is Iterable) {
        return value.map((Object? item) => '$item').toList(growable: false);
      }
      return null;
    }

    final List<String>? resolvedScopes = scopes != null
        ? scopes.toList(growable: false)
        : parseStringList(infoCopy['scopes']);

    return KmsEncryptedCredentials(
      token: infoCopy['token'] as String?,
      refreshToken: infoCopy['refresh_token'] as String?,
      idToken: infoCopy['id_token'] as String?,
      tokenUri: infoCopy['token_uri'] as String?,
      clientId: infoCopy['client_id'] as String?,
      clientSecret: infoCopy['client_secret'] as String?,
      scopes: resolvedScopes,
      defaultScopes: parseStringList(infoCopy['default_scopes']),
      grantedScopes: parseStringList(infoCopy['granted_scopes']),
      quotaProjectId: infoCopy['quota_project_id'] as String?,
      expiry: parsedExpiry,
      raptToken: infoCopy['rapt_token'] as String?,
      universeDomain:
          (infoCopy['universe_domain'] as String?) ?? 'googleapis.com',
      account: infoCopy['account'] as String?,
      enableReauthRefresh: (infoCopy['enable_reauth_refresh'] as bool?) ?? false,
      kmsKeyName: resolvedKmsKeyName,
      wrappedDek: wrappedDek,
      kmsClient: kmsClient,
    );
  }

  /// OAuth2 access token.
  String? token;

  /// OAuth2 refresh token.
  String? refreshToken;

  /// OpenID Connect ID token, if any.
  String? idToken;

  /// OAuth2 token endpoint URI.
  String? tokenUri;

  /// OAuth2 client identifier.
  String? clientId;

  /// OAuth2 client secret.
  String? clientSecret;

  /// Requested OAuth2 scopes.
  List<String>? scopes;

  /// Default OAuth2 scopes.
  List<String>? defaultScopes;

  /// Google Cloud quota project identifier.
  String? quotaProjectId;

  /// Access token expiration timestamp in UTC.
  DateTime? expiry;

  /// Reauthentication Proof Token (RAPT).
  String? raptToken;

  /// Optional custom refresh handler callback.
  Object? refreshHandler;

  /// Whether reauthentication refresh is enabled.
  bool enableReauthRefresh;

  /// Granted OAuth2 scopes.
  List<String>? grantedScopes;

  /// Universe domain (defaults to `'googleapis.com'`).
  String universeDomain;

  /// Associated account name or email.
  String? account;

  /// Optional trust boundary configuration.
  Object? trustBoundary;

  /// Cloud KMS key resource name used to envelope-encrypt sensitive fields.
  String? kmsKeyName;

  /// Base64-encoded KMS-wrapped DEK most recently produced or loaded.
  String? wrappedDek;

  /// Optional custom [KmsClient] used for encryption and decryption.
  KmsClient? kmsClient;

  /// Serializes these credentials to a JSON map, encrypting sensitive fields
  /// when [kmsKeyName] is configured.
  Map<String, Object?> toMap({Iterable<String>? strip}) {
    String? formattedExpiry;
    if (expiry != null) {
      final String iso = expiry!.toUtc().toIso8601String();
      formattedExpiry = iso.endsWith('Z') ? iso : '${iso}Z';
    }

    final Map<String, Object?> res = <String, Object?>{
      'token': token,
      'refresh_token': refreshToken,
      'token_uri': tokenUri,
      'client_id': clientId,
      'client_secret': clientSecret,
      'scopes': scopes,
      'default_scopes': defaultScopes,
      'granted_scopes': grantedScopes,
      'quota_project_id': quotaProjectId,
      'universe_domain': universeDomain,
      'account': account,
      'expiry': formattedExpiry,
      'rapt_token': raptToken,
    };

    if (kmsKeyName != null && kmsKeyName!.isNotEmpty) {
      final EncryptedCredentialsResult encrypted = encryptCredentials(
        kmsKeyName: kmsKeyName!,
        token: res['token'] as String?,
        refreshToken: res['refresh_token'] as String?,
        clientSecret: res['client_secret'] as String?,
        raptToken: res['rapt_token'] as String?,
        kmsClient: kmsClient,
      );
      if (res['token'] != null && encrypted.encryptedToken != null) {
        res['token'] = '$kmsCiphertextPrefix${encrypted.encryptedToken}';
      }
      if (res['refresh_token'] != null &&
          encrypted.encryptedRefreshToken != null) {
        res['refresh_token'] =
            '$kmsCiphertextPrefix${encrypted.encryptedRefreshToken}';
      }
      if (res['client_secret'] != null &&
          encrypted.encryptedClientSecret != null) {
        res['client_secret'] =
            '$kmsCiphertextPrefix${encrypted.encryptedClientSecret}';
      }
      if (res['rapt_token'] != null && encrypted.encryptedRaptToken != null) {
        res['rapt_token'] =
            '$kmsCiphertextPrefix${encrypted.encryptedRaptToken}';
      }
      wrappedDek = encrypted.wrappedDek;
      res['wrapped_dek'] = wrappedDek;
      res['kms_key_name'] = kmsKeyName;
    }

    final Set<String> stripSet = strip == null
        ? const <String>{}
        : strip.toSet();
    final Map<String, Object?> filtered = <String, Object?>{};
    res.forEach((String k, Object? v) {
      if (v != null && !stripSet.contains(k)) {
        filtered[k] = v;
      }
    });
    return filtered;
  }

  /// Serializes these credentials to a JSON string, encrypting sensitive fields
  /// when [kmsKeyName] is configured.
  String toJson({Iterable<String>? strip}) {
    return jsonEncode(toMap(strip: strip));
  }
}
