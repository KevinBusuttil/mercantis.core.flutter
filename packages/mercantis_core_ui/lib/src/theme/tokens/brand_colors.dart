import 'package:flutter/material.dart';

class MercantisBrandColors {
  const MercantisBrandColors._();

  static const Color primary = Color(0xFF4A6FA5);

  static const Color accentSales = Color(0xFF7B5BFF);
  static const Color accentPurchase = Color(0xFF1FB6A5);
  static const Color accentInventory = Color(0xFFE07A1F);
  static const Color accentDelivery = Color(0xFFE54B6F);
  static const Color accentFinance = Color(0xFF3D8BFD);
  static const Color accentApprovals = Color(0xFFFFB020);
  static const Color accentReports = Color(0xFF6E45B0);
  static const Color accentSetup = Color(0xFF6B7280);
  static const Color accentHome = Color(0xFF111827);
  // Rust red — mirrors Swift PR #126 (`.manufacturing` tone). Sits
  // between `accentInventory` (orange) and `accentDelivery` (pink) on
  // the wheel so manufacturing reads as "warmer than ops, less alarmist
  // than delivery exceptions".
  static const Color accentManufacturing = Color(0xFFD4525C);

  static const Color statusDraft = Color(0xFF9CA3AF);
  static const Color statusPending = Color(0xFFFFB020);
  static const Color statusSubmitted = Color(0xFF1FB6A5);
  static const Color statusApproved = Color(0xFF22C55E);
  static const Color statusCancelled = Color(0xFFE54B6F);
  static const Color statusOverdue = Color(0xFFEF4444);
  static const Color statusPaid = Color(0xFF22C55E);
  static const Color statusInfo = Color(0xFF3D8BFD);
}

/// Maps a workspace id (e.g. `'selling'`, `'buying'`, `'manufacturing'`)
/// to the accent colour the shell should paint into the workspace
/// chrome and selection highlights. Mirrors Swift's
/// `MercantisTheme.accentColor(for: MercantisModuleTone)` switch so
/// Core and Hub agree on the per-module palette.
///
/// Returns `null` for unknown ids; the shell falls back to the theme's
/// `ColorScheme.primary`.
Color? mercantisWorkspaceAccent(String? workspaceId) {
  switch (workspaceId) {
    case 'selling':
    case 'sales':
    case 'crm':
      return MercantisBrandColors.accentSales;
    case 'buying':
    case 'purchase':
      return MercantisBrandColors.accentPurchase;
    case 'stock':
    case 'inventory':
      return MercantisBrandColors.accentInventory;
    case 'accounting':
    case 'finance':
      return MercantisBrandColors.accentFinance;
    case 'manufacturing':
      return MercantisBrandColors.accentManufacturing;
    case 'setup':
    case 'system':
      return MercantisBrandColors.accentSetup;
    case 'home':
    case 'platform':
      return MercantisBrandColors.accentHome;
    default:
      return null;
  }
}
