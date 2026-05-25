import 'package:flutter/widgets.dart';

class QuickAction {
  const QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    this.docType,
    this.routeName,
    this.color,
    this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final String? docType;
  final String? routeName;
  final Color? color;
  final String? description;

  bool get opensNewDocument => docType != null && routeName == null;
}
