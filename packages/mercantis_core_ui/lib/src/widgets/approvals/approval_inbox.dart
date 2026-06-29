import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/tokens/brand_colors.dart';
import '../../theme/tokens/radius.dart';
import '../../theme/tokens/spacing.dart';
import '../empty_state.dart';
import '../status_chip.dart';
import 'approval_inbox_service.dart';

class ApprovalInboxList extends ConsumerWidget {
  const ApprovalInboxList({super.key, this.limit, this.dense = false});

  final int? limit;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(pendingApprovalsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load approvals: $e', style: theme.textTheme.bodySmall),
      ),
      data: (entries) {
        final shown = limit == null ? entries : entries.take(limit!).toList();
        if (shown.isEmpty) {
          return const EmptyState(
            title: 'All caught up',
            message: 'No approvals waiting for you.',
            icon: Icons.check_circle_outline,
          );
        }
        return ListView.separated(
          padding: dense ? EdgeInsets.zero : const EdgeInsets.all(MercantisSpacing.lg),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(height: MercantisSpacing.sm),
          itemBuilder: (context, i) {
            final e = shown[i];
            return _ApprovalTile(entry: e);
          },
        );
      },
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  const _ApprovalTile({required this.entry});
  final ApprovalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rMd,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(entry.route),
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MercantisBrandColors.accentApprovals.withValues(alpha: 0.15),
                  borderRadius: MercantisRadius.rMd,
                ),
                alignment: Alignment.center,
                child: Icon(
                  entry.icon ?? Icons.fact_check_outlined,
                  color: MercantisBrandColors.accentApprovals,
                  size: 18,
                ),
              ),
              const SizedBox(width: MercantisSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.amount != null) ...[
                          const SizedBox(width: MercantisSpacing.sm),
                          Text(
                            entry.amount!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entry.docType} · ${entry.requestedBy}'
                            '${entry.subtitle != null ? ' · ${entry.subtitle}' : ''}',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const StatusChip(
                          label: 'Pending',
                          tone: StatusTone.pending,
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
