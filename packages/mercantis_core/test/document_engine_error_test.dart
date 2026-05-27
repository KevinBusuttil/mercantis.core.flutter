import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// Mirrors the Swift PR #118 contract: every case of
/// [DocumentEngineError] produces a friendly, end-user-readable message
/// via [humanMessage], and `validationFailed` collapses a single stage
/// error to its message verbatim (so a form field error reads naturally)
/// while larger lists become a bulleted summary.
void main() {
  group('DocumentEngineError.humanMessage', () {
    test('docTypeNotFound names the missing id', () {
      final err = DocumentEngineError.docTypeNotFound('Customer');
      expect(err.humanMessage, contains('"Customer"'));
      expect(err.humanMessage, contains("isn't registered"));
    });

    test('notSubmittable explains why submit failed', () {
      final err = DocumentEngineError.notSubmittable('Note');
      expect(err.humanMessage, contains('"Note"'));
      expect(err.humanMessage, contains("can't be submitted"));
    });

    test('invalidDocStatusTransition renders Draft/Submitted/Cancelled', () {
      final err = DocumentEngineError.invalidDocStatusTransition(
        from: 0,
        to: 2,
        id: 'SO-001',
      );
      expect(err.humanMessage, contains('SO-001'));
      expect(err.humanMessage, contains('Draft'));
      expect(err.humanMessage, contains('Cancelled'));
    });

    test('fieldImmutableAfterSubmit calls out the field key', () {
      final err = DocumentEngineError.fieldImmutableAfterSubmit(
        fieldKey: 'customer',
        docType: 'Sales Order',
      );
      expect(err.humanMessage, contains('"customer"'));
      expect(err.humanMessage, contains("can't be changed"));
    });

    test('cancelBlockedByLinks previews up to three blocking ids', () {
      final err = DocumentEngineError.cancelBlockedByLinks(
        id: 'SI-001',
        blockingIds: ['A', 'B', 'C', 'D', 'E'],
      );
      expect(err.humanMessage, contains('SI-001'));
      expect(err.humanMessage, contains('A, B, C'));
      expect(err.humanMessage, contains('(and 2 more)'));
    });

    test('cannotDeleteSubmitted suggests cancelling first', () {
      final err = DocumentEngineError.cannotDeleteSubmitted('SO-9');
      expect(err.humanMessage, contains('SO-9'));
      expect(err.humanMessage, contains('Cancel it first'));
    });

    test('concurrencyConflict suggests reloading', () {
      final err = DocumentEngineError.concurrencyConflict('SO-9');
      expect(err.humanMessage, contains('SO-9'));
      expect(err.humanMessage, contains('Reload'));
    });

    test('malformedRow flags an incompatible payload', () {
      const err = DocumentEngineError.malformedRow('row 17');
      expect(err.humanMessage, contains("couldn't be read"));
    });

    group('validationFailed', () {
      test('empty list still produces a fallback sentence', () {
        final err = DocumentEngineError.validationFailed(const []);
        expect(err.humanMessage, contains("couldn't be saved"));
      });

      test('single error collapses to that message verbatim', () {
        final err = DocumentEngineError.validationFailed(const [
          ValidationError(
            stage: 'RequiredField',
            fieldKey: 'customer_type',
            message: 'Customer Type is required',
          ),
        ]);
        expect(err.humanMessage, 'Customer Type is required');
      });

      test('multiple errors render as a short bulleted summary', () {
        final err = DocumentEngineError.validationFailed(const [
          ValidationError(stage: 'RequiredField', message: 'Name is required'),
          ValidationError(stage: 'RequiredField', message: 'Date is required'),
        ]);
        final msg = err.humanMessage;
        expect(msg, contains("Couldn't save"));
        expect(msg, contains('• Name is required'));
        expect(msg, contains('• Date is required'));
      });

      test('more than four errors are summarised with a count + ellipsis', () {
        final errors = List.generate(
          6,
          (i) => ValidationError(stage: 's', message: 'problem $i'),
        );
        final err = DocumentEngineError.validationFailed(errors);
        final msg = err.humanMessage;
        expect(msg, startsWith('6 problems prevented the save:'));
        expect(msg, contains('• problem 0'));
        expect(msg, contains('• problem 3'));
        // Cap respected: 4 bullets shown, then an ellipsis bullet.
        expect(msg, contains('• …'));
        expect(msg, isNot(contains('• problem 4')));
      });
    });
  });
}
