import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Editor for `FieldType.geolocation`. Stores a coordinate as a `"lat,lng"`
/// string and edits it through two numeric inputs with range validation. Kept
/// plugin-free (manual entry / paste) so it carries no native dependency; a
/// device-GPS "capture" button can layer on later behind a location plugin.
class GeolocationField extends StatefulWidget {
  const GeolocationField({
    super.key,
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  /// Split a stored `"lat,lng"` value into its parsed parts (either may be null).
  static ({double? lat, double? lng}) parse(String? v) {
    if (v == null || v.trim().isEmpty) return (lat: null, lng: null);
    final parts = v.split(',');
    double? at(int i) =>
        parts.length > i ? double.tryParse(parts[i].trim()) : null;
    return (lat: at(0), lng: at(1));
  }

  @override
  State<GeolocationField> createState() => _GeolocationFieldState();
}

class _GeolocationFieldState extends State<GeolocationField> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;

  @override
  void initState() {
    super.initState();
    final p = GeolocationField.parse(widget.value);
    _lat = TextEditingController(text: p.lat?.toString() ?? '');
    _lng = TextEditingController(text: p.lng?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant GeolocationField old) {
    super.didUpdateWidget(old);
    // Re-seed when the value is reset externally (e.g. a fresh record).
    if (widget.value != old.value && widget.value != _combined()) {
      final p = GeolocationField.parse(widget.value);
      _lat.text = p.lat?.toString() ?? '';
      _lng.text = p.lng?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  String? _combined() {
    final lat = _lat.text.trim();
    final lng = _lng.text.trim();
    if (lat.isEmpty && lng.isEmpty) return null;
    return '$lat,$lng';
  }

  void _emit() => widget.onChanged(_combined());

  String? _rangeError() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat != null && (lat < -90 || lat > 90)) {
      return 'Latitude must be between -90 and 90.';
    }
    if (lng != null && (lng < -180 || lng > 180)) {
      return 'Longitude must be between -180 and 180.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _rangeError();
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))];
    const keyboard = TextInputType.numberWithOptions(decimal: true, signed: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.required ? '${widget.label} *' : widget.label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                readOnly: widget.readOnly,
                keyboardType: keyboard,
                inputFormatters: formatters,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.my_location),
                ),
                onChanged: (_) => setState(_emit),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lng,
                readOnly: widget.readOnly,
                keyboardType: keyboard,
                inputFormatters: formatters,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(_emit),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
