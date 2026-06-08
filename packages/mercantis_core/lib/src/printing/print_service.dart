import '../document_engine/document.dart';
import 'pdf_print_renderer.dart';
import 'plain_text_print_renderer.dart';
import 'print_format.dart';
import 'print_renderer.dart';

/// High-level print API (ADR-044) for Hub and other host apps.
///
/// A thin coordinator: it keeps a registry of formats and letter heads
/// (typically populated from an app manifest at install time) and dispatches to
/// a pluggable renderer keyed by [PrintOutputKind].
class PrintService {
  final Map<String, PrintFormat> _formats = {};
  final Map<String, LetterHead> _letterHeads = {};
  final Map<PrintOutputKind, PrintRenderer> _renderers;

  PrintService({List<PrintRenderer>? renderers})
      : _renderers = {
          for (final r in (renderers ?? defaultRenderers())) r.outputKind: r,
        };

  /// Default renderer set: plain text + PDF.
  static List<PrintRenderer> defaultRenderers() =>
      const [PlainTextPrintRenderer(), PdfPrintRenderer()];

  // Registration

  void registerFormat(PrintFormat format) => _formats[format.id] = format;
  void registerLetterHead(LetterHead letterHead) =>
      _letterHeads[letterHead.id] = letterHead;
  void unregisterFormat(String formatId) => _formats.remove(formatId);
  void unregisterLetterHead(String letterHeadId) =>
      _letterHeads.remove(letterHeadId);

  List<String> registeredFormatIds() => _formats.keys.toList();

  List<PrintFormat> formatsForDocType(String docType) =>
      _formats.values.where((f) => f.docType == docType).toList();

  // Render

  /// Render [document] with the format identified by [formatId] to bytes of
  /// [kind]. Throws [PrintServiceException] if the format is unknown, no
  /// renderer is configured for the kind, or the format's DocType doesn't match
  /// the document.
  Future<PrintRenderResult> render({
    required String formatId,
    required Document document,
    required PrintOutputKind kind,
    DateTime? now,
  }) {
    final format = _formats[formatId];
    if (format == null) {
      throw PrintServiceException.unknownFormat(formatId);
    }
    final renderer = _renderers[kind];
    if (renderer == null) {
      throw PrintServiceException.noRendererForKind(kind);
    }
    if (format.docType != document.docType) {
      throw PrintServiceException.docTypeMismatch(
          formatId, format.docType, document.docType);
    }

    final letterHead = format.letterHeadId == null
        ? null
        : _letterHeads[format.letterHeadId];
    return renderer.render(PrintRenderContext(
      format: format,
      document: document,
      letterHead: letterHead,
      now: now,
    ));
  }
}

class PrintServiceException implements Exception {
  final String message;
  const PrintServiceException(this.message);

  factory PrintServiceException.unknownFormat(String formatId) =>
      PrintServiceException('No print format registered with id "$formatId".');

  factory PrintServiceException.noRendererForKind(PrintOutputKind kind) =>
      PrintServiceException('No renderer configured for ${kind.name}.');

  factory PrintServiceException.docTypeMismatch(
          String formatId, String expected, String actual) =>
      PrintServiceException(
          'Format "$formatId" is for "$expected" but the document is "$actual".');

  @override
  String toString() => 'PrintServiceException: $message';
}
