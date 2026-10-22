import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'backup_crypto.dart';

/// The public, unencrypted part of a backup file. It holds only what is
/// needed to decrypt (key-derivation salt and settings, cipher layout) and to
/// say what made the file. No business data: company names, totals and the
/// file list live in the encrypted manifest.
class BackupHeader {
  const BackupHeader({
    required this.formatVersion,
    required this.createdAt,
    required this.producer,
    required this.kdf,
    required this.noncePrefix,
    this.segmentSize = BackupCipher.segmentSize,
  });

  static const currentFormat = 1;
  static const cipher = 'AES-256-GCM-STREAM';

  final int formatVersion;
  final DateTime createdAt;
  final String producer;
  final BackupKdfParams kdf;
  final List<int> noncePrefix;
  final int segmentSize;

  Map<String, Object?> toJson() => {
        'format': formatVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
        'producer': producer,
        'cipher': cipher,
        'segment_size': segmentSize,
        'nonce_prefix': base64Encode(noncePrefix),
        'kdf': kdf.toJson(),
      };

  factory BackupHeader.fromJson(Map<String, Object?> j) {
    final format = j['format'];
    if (format is! int) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    if (format > currentFormat) {
      throw const BackupException(
          BackupException.unsupportedFormat,
          'This backup was made by a newer version of Atlas. Update Atlas, '
          'then restore it.');
    }
    if (j['cipher'] != cipher) {
      throw const BackupException(BackupException.unsupportedFormat,
          'This backup uses an encryption format this version cannot read.');
    }
    final segment = j['segment_size'];
    final prefix = j['nonce_prefix'];
    final kdf = j['kdf'];
    final created = DateTime.tryParse('${j['created_at']}');
    if (segment is! int ||
        segment < 1024 ||
        segment > (16 << 20) ||
        prefix is! String ||
        kdf is! Map ||
        created == null) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    final prefixBytes = base64Decode(prefix);
    if (prefixBytes.length != BackupCipher.noncePrefixLength) {
      throw const BackupException(
          BackupException.damaged, 'The backup header is damaged.');
    }
    return BackupHeader(
      formatVersion: format,
      createdAt: created,
      producer: '${j['producer'] ?? ''}',
      kdf: BackupKdfParams.fromJson(Map<String, Object?>.from(kdf)),
      noncePrefix: prefixBytes,
      segmentSize: segment,
    );
  }
}

/// On-disk layout:
///
/// ```text
/// "ATLASBAK"                      8-byte magic
/// u32 header length, header JSON  public BackupHeader (UTF-8)
/// { u32 length, sealed segment }  AES-256-GCM segments to end of file
/// ```
///
/// The plaintext carried by the segments is a sequence of records:
/// `u8 kind, u32 name length, name (UTF-8), u64 length, bytes`, where kind is
/// `M` (the JSON manifest, always first), `F` (a file) or `E` (end; nothing may
/// follow). Integers are big-endian.
abstract final class BackupArchive {
  static const magic = [0x41, 0x54, 0x4C, 0x41, 0x53, 0x42, 0x41, 0x4B];
  static const kindManifest = 0x4D; // M
  static const kindFile = 0x46; // F
  static const kindEnd = 0x45; // E

  /// Largest header accepted when reading.
  static const maxHeaderLength = 64 * 1024;

  /// Reject archive paths that could escape the extraction directory.
  static String safeRelativePath(String name) {
    final normalized = p.posix.normalize(name);
    if (name.isEmpty ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        p.posix.isAbsolute(name) ||
        normalized != name ||
        normalized.split('/').any((s) => s == '..' || s == '.' || s.isEmpty)) {
      throw BackupException(BackupException.unsafePath,
          'The backup contains an invalid file name ($name).');
    }
    return normalized;
  }
}

/// Streams records into an encrypted backup file.
class BackupArchiveWriter {
  BackupArchiveWriter._(this._file, this._header, this._headerBytes, this._key);

  final RandomAccessFile _file;
  final BackupHeader _header;
  final List<int> _headerBytes;
  final SecretKey _key;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _segmentIndex = 0;
  bool _closed = false;

  /// Create [path] and write the public header.
  static Future<BackupArchiveWriter> create(
      String path, BackupHeader header, SecretKey key) async {
    final headerBytes = utf8.encode(jsonEncode(header.toJson()));
    final file = await File(path).open(mode: FileMode.writeOnly);
    await file.writeFrom(BackupArchive.magic);
    await file.writeFrom(_u32(headerBytes.length));
    await file.writeFrom(headerBytes);
    return BackupArchiveWriter._(file, header, headerBytes, key);
  }

  Future<void> addManifest(Map<String, Object?> manifest) async {
    final bytes = utf8.encode(jsonEncode(manifest));
    await _recordHeader(
        BackupArchive.kindManifest, 'manifest.json', bytes.length);
    await _write(bytes);
  }

  Future<void> addBytes(String name, List<int> bytes) async {
    await _recordHeader(BackupArchive.kindFile, name, bytes.length);
    await _write(bytes);
  }

  /// Stream [source] in as [name]. Returns its SHA-256 (lower-case hex) and
  /// throws if the file's length changes while it is read.
  Future<String> addFile(String name, File source, int expectedLength) async {
    await _recordHeader(BackupArchive.kindFile, name, expectedLength);
    final sink = _DigestSink();
    final digest = hash.sha256.startChunkedConversion(sink);
    var seen = 0;
    await for (final chunk in source.openRead()) {
      seen += chunk.length;
      if (seen > expectedLength) break;
      digest.add(chunk);
      await _write(chunk);
    }
    digest.close();
    if (seen != expectedLength) {
      throw FileSystemException(
          'file changed while it was being backed up', source.path);
    }
    return sink.value.toString();
  }

  /// Write the end record, seal the final segment and flush to disk.
  Future<void> close() async {
    if (_closed) return;
    await _recordHeader(BackupArchive.kindEnd, '', 0);
    final rest = _pending.takeBytes();
    await _seal(rest, last: true);
    await _file.flush();
    await _file.close();
    _closed = true;
  }

  /// Close without finishing (used when a backup is abandoned).
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    await _file.close();
  }

  Future<void> _recordHeader(int kind, String name, int length) async {
    final nameBytes = utf8.encode(name);
    final b = BytesBuilder()
      ..addByte(kind)
      ..add(_u32(nameBytes.length))
      ..add(nameBytes)
      ..add(_u64(length));
    await _write(b.takeBytes());
  }

  Future<void> _write(List<int> bytes) async {
    _pending.add(bytes);
    // Keep at least one byte back so the final segment is never empty unless
    // the whole stream is: the last segment must carry the last-segment flag.
    while (_pending.length > _header.segmentSize) {
      final all = _pending.takeBytes();
      await _seal(all.sublist(0, _header.segmentSize), last: false);
      _pending.add(all.sublist(_header.segmentSize));
    }
  }

  Future<void> _seal(List<int> plaintext, {required bool last}) async {
    final sealed = await BackupCipher.sealSegment(
      key: _key,
      noncePrefix: _header.noncePrefix,
      index: _segmentIndex++,
      last: last,
      plaintext: plaintext,
      header: _headerBytes,
    );
    await _file.writeFrom(_u32(sealed.length));
    await _file.writeFrom(sealed);
  }
}

/// One file read back out of a backup.
class ExtractedEntry {
  const ExtractedEntry(this.name, this.length, this.sha256);
  final String name;
  final int length;
  final String sha256;
}

/// Reads and authenticates an encrypted backup file.
class BackupArchiveReader {
  BackupArchiveReader._(
      this._file, this.header, this._headerBytes, this._bodyStart);

  final RandomAccessFile _file;
  final BackupHeader header;
  final List<int> _headerBytes;
  final int _bodyStart;

  /// Open [path] and parse the public header. Throws [BackupException] when
  /// the file is not an Atlas backup or its header is unreadable.
  static Future<BackupArchiveReader> open(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      throw const BackupException(
          BackupException.notABackup, 'The backup file could not be found.');
    }
    final file = await f.open();
    try {
      final magic = await file.read(8);
      if (magic.length != 8 || !_equals(magic, BackupArchive.magic)) {
        throw const BackupException(
            BackupException.notABackup, 'This file is not an Atlas backup.');
      }
      final lenBytes = await file.read(4);
      if (lenBytes.length != 4) {
        throw const BackupException(
            BackupException.truncated, 'The backup file is incomplete.');
      }
      final len =
          ByteData.sublistView(Uint8List.fromList(lenBytes)).getUint32(0);
      if (len == 0 || len > BackupArchive.maxHeaderLength) {
        throw const BackupException(
            BackupException.damaged, 'The backup header is damaged.');
      }
      final headerBytes = await file.read(len);
      if (headerBytes.length != len) {
        throw const BackupException(
            BackupException.truncated, 'The backup file is incomplete.');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(headerBytes));
      } on FormatException {
        throw const BackupException(
            BackupException.damaged, 'The backup header is damaged.');
      }
      if (decoded is! Map) {
        throw const BackupException(
            BackupException.damaged, 'The backup header is damaged.');
      }
      final header = BackupHeader.fromJson(Map<String, Object?>.from(decoded));
      return BackupArchiveReader._(file, header, headerBytes, 8 + 4 + len);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  /// Decrypt and walk every record. The manifest (always first) is handed to
  /// [onManifest]; each file is streamed to the path [destinationFor] returns
  /// for its (validated, relative) name. Lengths are enforced and every file's
  /// SHA-256 is computed while it is written. Any authentication failure,
  /// truncation or trailing data throws [BackupException].
  Future<List<ExtractedEntry>> extract({
    required SecretKey key,
    required void Function(Map<String, Object?> manifest) onManifest,
    required String? Function(String relativeName) destinationFor,
  }) async {
    final source = _PlaintextSource(this, key);
    final entries = <ExtractedEntry>[];
    var sawManifest = false;
    while (true) {
      final kind = (await source.take(1)).single;
      final nameLen = _readU32(await source.take(4));
      if (nameLen > 4096) {
        throw const BackupException(
            BackupException.damaged, 'The backup file is damaged.');
      }
      final name = utf8.decode(await source.take(nameLen));
      final length = _readU64(await source.take(8));
      if (kind == BackupArchive.kindEnd) {
        if (!await source.atEnd()) {
          throw const BackupException(BackupException.damaged,
              'The backup file has unexpected data after its end.');
        }
        if (!sawManifest) {
          throw const BackupException(
              BackupException.damaged, 'The backup has no manifest.');
        }
        return entries;
      }
      if (kind == BackupArchive.kindManifest) {
        if (sawManifest || entries.isNotEmpty || length > (64 << 20)) {
          throw const BackupException(
              BackupException.damaged, 'The backup file is damaged.');
        }
        final bytes = await source.take(length);
        final Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const BackupException(
              BackupException.damaged, 'The backup manifest is damaged.');
        }
        if (decoded is! Map) {
          throw const BackupException(
              BackupException.damaged, 'The backup manifest is damaged.');
        }
        onManifest(Map<String, Object?>.from(decoded));
        sawManifest = true;
        continue;
      }
      if (kind != BackupArchive.kindFile || !sawManifest) {
        throw const BackupException(
            BackupException.damaged, 'The backup file is damaged.');
      }
      final rel = BackupArchive.safeRelativePath(name);
      // A null destination verifies the entry without writing it anywhere.
      final destination = destinationFor(rel);
      IOSink? sink;
      if (destination != null) {
        final target = File(destination);
        target.parent.createSync(recursive: true);
        sink = target.openWrite();
      }
      final digestSink = _DigestSink();
      final digest = hash.sha256.startChunkedConversion(digestSink);
      try {
        var remaining = length;
        while (remaining > 0) {
          final chunk = await source.takeUpTo(remaining);
          digest.add(chunk);
          sink?.add(chunk);
          remaining -= chunk.length;
        }
        await sink?.flush();
      } finally {
        await sink?.close();
      }
      digest.close();
      entries.add(ExtractedEntry(rel, length, digestSink.value.toString()));
    }
  }

  Future<(List<int>, bool)?> _segment(int index, int position) async {
    final total = await _file.length();
    if (position >= total) return null;
    await _file.setPosition(position);
    final lenBytes = await _file.read(4);
    if (lenBytes.length != 4) {
      throw const BackupException(
          BackupException.truncated, 'The backup file is incomplete.');
    }
    final len = ByteData.sublistView(Uint8List.fromList(lenBytes)).getUint32(0);
    if (len < BackupCipher.tagLength ||
        len > header.segmentSize + BackupCipher.tagLength) {
      throw const BackupException(
          BackupException.damaged, 'The backup file is damaged.');
    }
    final sealed = await _file.read(len);
    if (sealed.length != len) {
      throw const BackupException(
          BackupException.truncated, 'The backup file is incomplete.');
    }
    final end = position + 4 + len;
    return ([...sealed], end == total);
  }

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Pulls decrypted bytes across segment boundaries.
class _PlaintextSource {
  _PlaintextSource(this._reader, this._key) : _position = _reader._bodyStart;

  final BackupArchiveReader _reader;
  final SecretKey _key;
  int _position;
  int _index = 0;
  bool _sawLast = false;
  List<int> _buffer = const [];
  int _offset = 0;

  Future<bool> _fill() async {
    while (_offset >= _buffer.length) {
      if (_sawLast) return false;
      final seg = await _reader._segment(_index, _position);
      if (seg == null) {
        throw const BackupException(
            BackupException.truncated, 'The backup file is incomplete.');
      }
      final (sealed, last) = seg;
      _buffer = await BackupCipher.openSegment(
        key: _key,
        noncePrefix: _reader.header.noncePrefix,
        index: _index,
        last: last,
        sealed: sealed,
        header: _reader._headerBytes,
      );
      _offset = 0;
      _position += 4 + sealed.length;
      _index++;
      _sawLast = last;
    }
    return true;
  }

  Future<List<int>> take(int n) async {
    final out = BytesBuilder(copy: false);
    var need = n;
    while (need > 0) {
      final chunk = await takeUpTo(need);
      out.add(chunk);
      need -= chunk.length;
    }
    return out.takeBytes();
  }

  Future<List<int>> takeUpTo(int n) async {
    if (!await _fill()) {
      throw const BackupException(
          BackupException.truncated, 'The backup file is incomplete.');
    }
    final available = _buffer.length - _offset;
    final count = available < n ? available : n;
    final chunk = _buffer.sublist(_offset, _offset + count);
    _offset += count;
    return chunk;
  }

  Future<bool> atEnd() async => !await _fill() && _sawLast;
}

class _DigestSink implements Sink<hash.Digest> {
  late hash.Digest value;
  @override
  void add(hash.Digest data) => value = data;
  @override
  void close() {}
}

List<int> _u32(int v) {
  final b = ByteData(4)..setUint32(0, v);
  return b.buffer.asUint8List();
}

List<int> _u64(int v) {
  final b = ByteData(8)
    ..setUint32(0, v ~/ 0x100000000)
    ..setUint32(4, v % 0x100000000);
  return b.buffer.asUint8List();
}

int _readU32(List<int> b) =>
    ByteData.sublistView(Uint8List.fromList(b)).getUint32(0);

int _readU64(List<int> b) {
  final d = ByteData.sublistView(Uint8List.fromList(b));
  return d.getUint32(0) * 0x100000000 + d.getUint32(4);
}
