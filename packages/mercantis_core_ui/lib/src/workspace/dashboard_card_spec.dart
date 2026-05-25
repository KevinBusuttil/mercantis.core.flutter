import 'package:flutter/widgets.dart';

enum DashboardCardKind { kpi, list, chart, custom }

class DashboardCardSpec {
  const DashboardCardSpec({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.span = 1,
    this.dataSourceId,
    this.config = const {},
  });

  final String id;
  final String title;
  final DashboardCardKind kind;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final int span;
  final String? dataSourceId;
  final Map<String, dynamic> config;

  const DashboardCardSpec.kpi({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.span = 1,
    this.dataSourceId,
    this.config = const {},
  }) : kind = DashboardCardKind.kpi;

  const DashboardCardSpec.list({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.span = 2,
    this.dataSourceId,
    this.config = const {},
  }) : kind = DashboardCardKind.list;

  const DashboardCardSpec.chart({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.span = 2,
    this.dataSourceId,
    this.config = const {},
  }) : kind = DashboardCardKind.chart;

  const DashboardCardSpec.custom({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.span = 1,
    this.dataSourceId,
    this.config = const {},
  }) : kind = DashboardCardKind.custom;
}
