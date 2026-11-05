import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Why a backup could not be opened. [message] is written for the person
/// restoring, not for a developer.
class BackupException implements Exception {
  const BackupException(this.code, this.message);

  /// Stable machine code (tests, support logs).
  final String code;
  final String message;

  static const notABackup = 'not_a_backup';
  static const unsupportedFormat = 'unsupported_format';
  static const wrongPassphraseOrDamaged = 'wrong_passphrase_or_damaged';
  static const truncated = 'truncated';
  static const damaged = 'damaged';
  static const incompatible = 'incompatible';
  static const weakPassphrase = 'weak_passphrase';
  static const unsafePath = 'unsafe_path';

  @override
  String toString() => 'BackupException($code): $message';
}

/// Password-based key derivation settings, stored in the backup's public
/// header so a backup stays readable if the defaults change later.
class BackupKdfParams {
  const BackupKdfParams({
    required this.salt,
    this.memoryKiB = defaultMemoryKiB,
    this.iterations = defaultIterations,
    this.parallelism = 1,
  });

  /// Argon2id, RFC 9106's second recommended profile: 64 MiB, 3 passes.
  static const defaultMemoryKiB = 65536;
  static const defaultIterations = 3;

  /// Bounds accepted when READING a header, so a crafted file cannot make the
  /// restore allocate gigabytes or spin for hours.
  static const maxMemoryKiB = 1048576;
  static const maxIterations = 20;

  static const algorithm = 'argon2id';

  final List<int> salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Fresh params with a random 16-byte salt.
  factory BackupKdfParams.generate({
    int memoryKiB = defaultMemoryKiB,
    int iterations = defaultIterations,
  }) =>
      BackupKdfParams(
        salt: BackupCipher.randomBytes(16),
        memoryKiB: memoryKiB,
        iterations: iterations,
      );

  Map<String, Object?> toJson() => {
        'algorithm': algorithm,
        'salt': base64Encode(salt),
        'memory_kib': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  factory BackupKdfParams.fromJson(Map<String, Object?> j) {
    if (j['algorithm'] != algorithm) {
      throw const BackupException(BackupException.unsupportedFormat,
          'This backup uses a key format this version of Atlas cannot read.');
    }
    final memory = j['memory_kib'];
    final iterations = j['iterations'];
    final parallelism = j['parallelism'];
    final salt = j['salt'];
    if (memory is! int ||
        iterations is! int ||
        parallelism is! int ||
        salt is! String ||
        memory < 8 ||
        memory > maxMemoryKiB ||
        iterations < 1 ||
        iterations > maxIterations ||
        parallelism < 1 ||
        parallelism > 16) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    return BackupKdfParams(
      salt: base64Decode(salt),
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }
}

/// Authenticated encryption for Atlas backups.
///
/// Primitives come from `package:cryptography` (maintained, widely used):
/// Argon2id turns the recovery passphrase into a 256-bit key, and AES-256-GCM
/// encrypts the archive. Nothing here invents a primitive.
///
/// The archive is encrypted in fixed-size segments so a large attachment store
/// never has to sit in memory. Segmenting follows the published STREAM
/// construction (Hoang, Reyhanitabar, Rogaway, Vizár, CRYPTO 2015), as used by
/// Google Tink's streaming AEAD: each segment's 96-bit nonce is
/// `7-byte random prefix || 4-byte big-endian segment counter || 1-byte
/// last-segment flag`, and the public header is the associated data of every
/// segment. A reordered, dropped, duplicated or appended segment, a truncated
/// file or an edited header therefore fails authentication. A fresh random
/// salt per backup gives every backup its own key, so nonces never repeat
/// under one key.
///
/// The passphrase is never stored, in the backup or anywhere else.
abstract final class BackupCipher {
  /// Plaintext bytes per segment.
  static const segmentSize = 1 << 20;
  static const noncePrefixLength = 7;
  static const tagLength = 16;

  /// Minimum passphrase length enforced when CREATING a backup.
  static const minPassphraseLength = 12;

  static final _aead = AesGcm.with256bits();

  /// Reject passphrases too short to resist offline guessing once a backup
  /// file is stolen.
  static void checkPassphrase(String passphrase) {
    if (passphrase.trim().length < minPassphraseLength) {
      throw const BackupException(
          BackupException.weakPassphrase,
          'Use a recovery passphrase of at least $minPassphraseLength '
          'characters. A short sentence works well.');
    }
  }

  static Future<SecretKey> deriveKey(
      String passphrase, BackupKdfParams params) {
    final argon = Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 32,
    );
    return argon.deriveKeyFromPassword(
        password: passphrase, nonce: params.salt);
  }

  static List<int> segmentNonce(List<int> prefix, int index, bool last) {
    if (prefix.length != noncePrefixLength) {
      throw ArgumentError('nonce prefix must be $noncePrefixLength bytes');
    }
    if (index < 0 || index > 0xFFFFFFFF) {
      throw RangeError('segment index out of range');
    }
    final n = Uint8List(12);
    n.setRange(0, noncePrefixLength, prefix);
    ByteData.sublistView(n).setUint32(noncePrefixLength, index);
    n[11] = last ? 1 : 0;
    return n;
  }

  /// Encrypt one segment; returns ciphertext || 16-byte tag.
  static Future<Uint8List> sealSegment({
    required SecretKey key,
    required List<int> noncePrefix,
    required int index,
    required bool last,
    required List<int> plaintext,
    required List<int> header,
  }) async {
    final box = await _aead.encrypt(
      plaintext,
      secretKey: key,
      nonce: segmentNonce(noncePrefix, index, last),
      aad: header,
    );
    final out = Uint8List(box.cipherText.length + tagLength);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// Decrypt one segment produced by [sealSegment]. Throws [BackupException]
  /// when authentication fails (wrong passphrase, tampering or damage).
  static Future<List<int>> openSegment({
    required SecretKey key,
    required List<int> noncePrefix,
    required int index,
    required bool last,
    required List<int> sealed,
    required List<int> header,
  }) async {
    if (sealed.length < tagLength) {
      throw const BackupException(
          BackupException.damaged, 'The backup file is damaged.');
    }
    final split = sealed.length - tagLength;
    try {
      return await _aead.decrypt(
        SecretBox(
          sealed.sublist(0, split),
          nonce: segmentNonce(noncePrefix, index, last),
          mac: Mac(sealed.sublist(split)),
        ),
        secretKey: key,
        aad: header,
      );
    } on SecretBoxAuthenticationError {
      // Once segment 0 authenticates the passphrase is known to be right, so
      // any later failure is damage or tampering.
      throw BackupException(
          index == 0
              ? BackupException.wrongPassphraseOrDamaged
              : BackupException.damaged,
          index == 0
              ? 'The passphrase is wrong, or the backup file is damaged.'
              : 'The backup file is damaged or was changed after it was made.');
    }
  }

  /// Open a wrapped 32-byte key (ciphertext || tag) under [kek].
  static Future<List<int>> openKey(
      SecretKey kek, List<int> nonce, List<int> wrapped, String aad,
      {required String wrongMessage}) async {
    if (wrapped.length != 32 + tagLength) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    try {
      return await _aead.decrypt(
        SecretBox(wrapped.sublist(0, 32),
            nonce: nonce, mac: Mac(wrapped.sublist(32))),
        secretKey: kek,
        aad: utf8.encode(aad),
      );
    } on SecretBoxAuthenticationError {
      throw BackupException(
          BackupException.wrongPassphraseOrDamaged, wrongMessage);
    }
  }

  static List<int> randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}

/// The passphrase-protected copy of a device backup key, carried in the
/// public header of every automatic backup.
///
/// Automatic backups cannot ask for the passphrase each time, so they are
/// encrypted under a random 256-bit **device key** kept in the platform's
/// secure storage. That key is useless on a replacement device, so every
/// automatic backup also carries this slot: the device key encrypted
/// (AES-256-GCM) under a key derived from the operator's recovery passphrase
/// with Argon2id. With the passphrase alone, any Atlas install can open the
/// backup. The passphrase itself is never stored; the slot is made once, when
/// automatic backup is switched on, and can be re-made to change it.
class BackupRecoverySlot {
  const BackupRecoverySlot({
    required this.keyId,
    required this.kdf,
    required this.nonce,
    required this.wrapped,
  });

  /// Public, non-secret identifier of the device key: lets a device tell
  /// whether it holds the key for a backup without trying to decrypt it.
  final String keyId;
  final BackupKdfParams kdf;
  final List<int> nonce;

  /// Device key ciphertext || 16-byte tag.
  final List<int> wrapped;

  static const _aad = 'atlas-backup-recovery-slot:v1:';

  static String keyIdOf(List<int> deviceKey) {
    final d = hash.sha256
        .convert([...utf8.encode('atlas-backup-key-id:v1:'), ...deviceKey]);
    return base64Url.encode(d.bytes.sublist(0, 12));
  }

  static Future<BackupRecoverySlot> wrap(String passphrase, List<int> deviceKey,
      {BackupKdfParams? kdf}) async {
    BackupCipher.checkPassphrase(passphrase);
    if (deviceKey.length != 32) {
      throw ArgumentError('device key must be 32 bytes');
    }
    final params = kdf ?? BackupKdfParams.generate();
    final kek = await BackupCipher.deriveKey(passphrase, params);
    final keyId = keyIdOf(deviceKey);
    final nonce = BackupCipher.randomBytes(12);
    final box = await AesGcm.with256bits().encrypt(deviceKey,
        secretKey: kek, nonce: nonce, aad: utf8.encode('$_aad$keyId'));
    return BackupRecoverySlot(
      keyId: keyId,
      kdf: params,
      nonce: nonce,
      wrapped: [...box.cipherText, ...box.mac.bytes],
    );
  }

  /// The device key, or [BackupException.wrongPassphraseOrDamaged].
  Future<List<int>> unwrap(String passphrase) async {
    final kek = await BackupCipher.deriveKey(passphrase, kdf);
    final key = await BackupCipher.openKey(kek, nonce, wrapped, '$_aad$keyId',
        wrongMessage: 'The recovery passphrase is wrong, or the backup file '
            'is damaged.');
    if (keyIdOf(key) != keyId) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    return key;
  }

  Map<String, Object?> toJson() => {
        'key_id': keyId,
        'kdf': kdf.toJson(),
        'nonce': base64Encode(nonce),
        'wrapped': base64Encode(wrapped),
      };

  factory BackupRecoverySlot.fromJson(Map<String, Object?> j) {
    final kdf = j['kdf'];
    final keyId = j['key_id'];
    final nonce = j['nonce'];
    final wrapped = j['wrapped'];
    if (kdf is! Map ||
        keyId is! String ||
        nonce is! String ||
        wrapped is! String) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    try {
      final n = base64Decode(nonce);
      final w = base64Decode(wrapped);
      if (n.length != 12 || w.length != 32 + BackupCipher.tagLength) {
        throw const FormatException();
      }
      return BackupRecoverySlot(
        keyId: keyId,
        kdf: BackupKdfParams.fromJson(Map<String, Object?>.from(kdf)),
        nonce: n,
        wrapped: w,
      );
    } on FormatException {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
  }
}

/// What an automatic backup is encrypted with: the device key (from secure
/// storage) and its [recovery] slot.
class BackupKeyring {
  BackupKeyring({required this.deviceKey, required this.recovery}) {
    if (deviceKey.length != 32 ||
        BackupRecoverySlot.keyIdOf(deviceKey) != recovery.keyId) {
      throw ArgumentError('the recovery slot does not belong to this key');
    }
  }

  final List<int> deviceKey;
  final BackupRecoverySlot recovery;

  String get keyId => recovery.keyId;

  /// A new random device key protected by [passphrase].
  static Future<BackupKeyring> create(String passphrase,
      {BackupKdfParams? kdf}) async {
    final key = BackupCipher.randomBytes(32);
    return BackupKeyring(
        deviceKey: key,
        recovery: await BackupRecoverySlot.wrap(passphrase, key, kdf: kdf));
  }
}

/// The per-backup content key, encrypted under the device key, as stored in
/// a keyring backup's header. Every backup gets a fresh random content key,
/// so segment nonces never repeat under one key however many backups the
/// device key protects.
class BackupContentKeySlot {
  const BackupContentKeySlot({required this.nonce, required this.wrapped});

  final List<int> nonce;
  final List<int> wrapped;

  static const _aad = 'atlas-backup-content-key:v1:';

  static Future<(BackupContentKeySlot, SecretKey)> create(
      List<int> deviceKey, String keyId) async {
    final content = BackupCipher.randomBytes(32);
    final nonce = BackupCipher.randomBytes(12);
    final box = await AesGcm.with256bits().encrypt(content,
        secretKey: SecretKey(deviceKey),
        nonce: nonce,
        aad: utf8.encode('$_aad$keyId'));
    return (
      BackupContentKeySlot(
          nonce: nonce, wrapped: [...box.cipherText, ...box.mac.bytes]),
      SecretKey(content),
    );
  }

  Future<SecretKey> open(List<int> deviceKey, String keyId) async =>
      SecretKey(await BackupCipher.openKey(
          SecretKey(deviceKey), nonce, wrapped, '$_aad$keyId',
          wrongMessage:
              'This device\'s backup key does not open this backup.'));

  Map<String, Object?> toJson() =>
      {'nonce': base64Encode(nonce), 'wrapped': base64Encode(wrapped)};

  factory BackupContentKeySlot.fromJson(Map<String, Object?> j) {
    try {
      final n = base64Decode('${j['nonce']}');
      final w = base64Decode('${j['wrapped']}');
      if (n.length != 12 || w.length != 32 + BackupCipher.tagLength) {
        throw const FormatException();
      }
      return BackupContentKeySlot(nonce: n, wrapped: w);
    } on FormatException {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
  }
}
