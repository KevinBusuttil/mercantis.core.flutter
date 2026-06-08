import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'attachment.dart';

/// Filesystem-backed byte store for attachments (ADR-043). Files are written
/// under `<root>/<documentId>/<attachmentId>` so a per-document `deleteAll` is
/// one directory-tree removal.
///
/// The store is intentionally dumb: it knows nothing about DocTypes,
/// permissions, or audit. Those concerns live one layer up in
/// `AttachmentManager`.
class AttachmentStore {
  /// Absolute path to the directory that holds all attachment bytes.
  final String rootPath;

  AttachmentStore(this.rootPath) {
    _ensureDir(rootPath);
  }

  /// Write [data] for [attachmentId] under [documentId]. Returns the relative
  /// storage path (`<documentId>/<attachmentId>`), recorded in the metadata
  /// row by `AttachmentManager`.
  String write(String documentId, String attachmentId, List<int> data) {
    final dir = p.join(rootPath, documentId);
    _ensureDir(dir);
    final target = File(p.join(dir, attachmentId));
    target.writeAsBytesSync(data, flush: true);
    return '$documentId/$attachmentId';
  }

  /// Read the bytes at [storagePath]. Throws [AttachmentException.notFound]
  /// when the file is missing.
  Uint8List read(String storagePath) {
    final file = File(_absolute(storagePath));
    if (!file.existsSync()) {
      throw AttachmentException.notFound(storagePath);
    }
    return file.readAsBytesSync();
  }

  bool exists(String storagePath) => File(_absolute(storagePath)).existsSync();

  /// Delete a single attachment file. Missing files are tolerated — the
  /// metadata row is the source of truth and may already be gone.
  void delete(String storagePath) {
    final file = File(_absolute(storagePath));
    if (file.existsSync()) file.deleteSync();
  }

  /// Recursively delete every file under `<root>/<documentId>/`.
  void deleteAll(String documentId) {
    final dir = Directory(p.join(rootPath, documentId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Lower-case hex SHA-256 of [data].
  static String sha256Hex(List<int> data) => sha256.convert(data).toString();

  String _absolute(String storagePath) =>
      p.joinAll([rootPath, ...p.posix.split(storagePath)]);

  void _ensureDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }
}
