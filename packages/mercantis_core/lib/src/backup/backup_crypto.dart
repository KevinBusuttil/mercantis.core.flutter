import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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

  static List<int> randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}
