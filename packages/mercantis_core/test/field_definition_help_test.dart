import 'package:test/test.dart';
import 'package:mercantis_core/mercantis_core.dart';

/// C4: `helpText` / `placeholder` field metadata must survive JSON round-trips
/// and copyWith so manifests can declare them and the form can render them.
void main() {
  test('helpText/placeholder round-trip through toJson/fromJson', () {
    const field = FieldDefinition(
      key: 'email',
      type: FieldType.data,
      label: 'Email',
      helpText: 'Used on invoices and the customer portal.',
      placeholder: 'name@business.com',
    );

    final json = field.toJson();
    expect(json['helpText'], 'Used on invoices and the customer portal.');
    expect(json['placeholder'], 'name@business.com');

    final decoded = FieldDefinition.fromJson(json);
    expect(decoded.helpText, field.helpText);
    expect(decoded.placeholder, field.placeholder);
  });

  test('omitted when null', () {
    const field =
        FieldDefinition(key: 'name', type: FieldType.data, label: 'Name');
    final json = field.toJson();
    expect(json.containsKey('helpText'), isFalse);
    expect(json.containsKey('placeholder'), isFalse);
    expect(FieldDefinition.fromJson(json).helpText, isNull);
  });

  test('copyWith preserves and overrides the new fields', () {
    const field = FieldDefinition(
      key: 'name',
      type: FieldType.data,
      label: 'Name',
      helpText: 'original',
    );
    expect(field.copyWith(label: 'Renamed').helpText, 'original');
    expect(field.copyWith(placeholder: 'ghost').placeholder, 'ghost');
    expect(field.copyWith(helpText: 'updated').helpText, 'updated');
  });
}
