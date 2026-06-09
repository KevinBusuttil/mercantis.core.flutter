import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  group('ColorField hex', () {
    test('parses #RRGGBB and bare RRGGBB to opaque colors', () {
      expect(ColorField.parseHex('#EF5350')?.toARGB32(), 0xFFEF5350);
      expect(ColorField.parseHex('EF5350')?.toARGB32(), 0xFFEF5350);
    });

    test('rejects malformed input', () {
      expect(ColorField.parseHex(null), isNull);
      expect(ColorField.parseHex(''), isNull);
      expect(ColorField.parseHex('#FFF'), isNull);
      expect(ColorField.parseHex('#ZZZZZZ'), isNull);
    });

    test('toHex round-trips through parseHex', () {
      const hex = '#26A69A';
      expect(ColorField.toHex(ColorField.parseHex(hex)!), hex);
    });
  });

  group('SignatureField strokes', () {
    test('encode/decode round-trips normalised strokes', () {
      final strokes = [
        [const Offset(0.1, 0.2), const Offset(0.3, 0.4)],
        [const Offset(0.5, 0.6)],
      ];
      final decoded =
          SignatureField.decodeStrokes(SignatureField.encodeStrokes(strokes));
      expect(decoded, hasLength(2));
      expect(decoded[0], hasLength(2));
      expect(decoded[0][1], const Offset(0.3, 0.4));
      expect(decoded[1].single, const Offset(0.5, 0.6));
    });

    test('decode tolerates null and malformed input', () {
      expect(SignatureField.decodeStrokes(null), isEmpty);
      expect(SignatureField.decodeStrokes(''), isEmpty);
      expect(SignatureField.decodeStrokes('not json'), isEmpty);
      expect(SignatureField.decodeStrokes('{"strokes":42}'), isEmpty);
    });
  });
}
