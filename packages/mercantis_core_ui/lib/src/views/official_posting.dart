import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

/// Host-supplied override for OFFICIAL document postings.
///
/// When registered and it claims a doctype, the form's Submit and Cancel
/// route through it instead of the local [DocumentEngine] — e.g. the Atlas
/// Team backend's posting authority, where the server validates, allocates
/// the gap-free number and posts GL/stock atomically. Drafts (save) are
/// never routed here: only the official lifecycle transitions.
///
/// Implementations should throw on failure (a [DocumentEngineError] or any
/// exception; the form surfaces the message) and are responsible for making
/// the posted state visible locally before returning (e.g. by running a
/// sync exchange), because the form re-fetches the document afterwards.
abstract class OfficialPostingOverride {
  /// Whether this override owns the official lifecycle of [docType].
  bool handles(String docType);

  Future<void> submit(WidgetRef ref, Document doc);

  Future<void> cancel(WidgetRef ref, Document doc);
}

/// Null by default: every doctype submits/cancels through the local engine
/// (Solo behaviour). The host overrides this in Team mode.
final officialPostingOverrideProvider =
    Provider<OfficialPostingOverride?>((_) => null);
