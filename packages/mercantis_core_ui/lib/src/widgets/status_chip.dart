import 'package:flutter/material.dart';
import '../theme/tokens/brand_colors.dart';
import '../theme/tokens/radius.dart';

enum StatusTone {
  draft,
  pending,
  submitted,
  approved,
  cancelled,
  overdue,
  paid,
  info,
  neutral,
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool dense;

  static StatusChip forDocStatus(int docStatus, {bool dense = false}) {
    return switch (docStatus) {
      0 => StatusChip(label: 'Draft', tone: StatusTone.draft, dense: dense),
      1 => StatusChip(label: 'Submitted', tone: StatusTone.submitted, dense: dense),
      2 => StatusChip(label: 'Cancelled', tone: StatusTone.cancelled, dense: dense),
      _ => StatusChip(label: 'Unknown', tone: StatusTone.neutral, dense: dense),
    };
  }

  Color get _baseColor {
    return switch (tone) {
      StatusTone.draft => MercantisBrandColors.statusDraft,
      StatusTone.pending => MercantisBrandColors.statusPending,
      StatusTone.submitted => MercantisBrandColors.statusSubmitted,
      StatusTone.approved => MercantisBrandColors.statusApproved,
      StatusTone.cancelled => MercantisBrandColors.statusCancelled,
      StatusTone.overdue => MercantisBrandColors.statusOverdue,
      StatusTone.paid => MercantisBrandColors.statusPaid,
      StatusTone.info => MercantisBrandColors.statusInfo,
      StatusTone.neutral => MercantisBrandColors.statusDraft,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _baseColor;
    final bg = color.withValues(alpha: 0.12);
    final fg = color;
    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: MercantisRadius.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: fg),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: dense ? 5 : 6,
              height: dense ? 5 : 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: dense ? 11 : 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
