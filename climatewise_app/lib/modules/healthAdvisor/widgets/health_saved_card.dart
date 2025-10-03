import 'package:flutter/material.dart';
import '../models/health_result_summary.dart';

class HealthSavedCard extends StatelessWidget {
  final HealthResultSummary item;
  final VoidCallback onForecastNow;
  final Future<bool> Function()? onConfirmAndDelete;
  final bool isDeleting;

  const HealthSavedCard({
    super.key,
    required this.item,
    required this.onForecastNow,
    this.onConfirmAndDelete,
    this.isDeleting = false,
  });

  Color _levelColor(BuildContext context, String level) {
    final theme = Theme.of(context);
    switch (level) {
      case 'Very High':
        return theme.colorScheme.error;
      case 'High':
        return Colors.orange;
      case 'Moderate':
        return Colors.amber;
      case 'Low':
        return Colors.teal;
      default:
        return theme.colorScheme.primary;
    }
  }

  String _sensitivityLabel(Sensitivity s) {
    switch (s) {
      case Sensitivity.sensitive:
        return 'Sensitive';
      case Sensitivity.relaxed:
        return 'Relaxed';
      case Sensitivity.normal:
      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = item.levelLabel;
    final levelColor = _levelColor(context, level);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: levelColor.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed, size: 16, color: levelColor),
                    const SizedBox(width: 6),
                    Text(
                      '${item.overallScore}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: levelColor),
                    ),
                    const SizedBox(width: 6),
                    Text(level, style: TextStyle(fontWeight: FontWeight.w600, color: levelColor)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.locationLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.favorite_outline, size: 18, color: Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Text(_sensitivityLabel(item.sensitivity),
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),

          const SizedBox(height: 10),

          if (item.diseases.isNotEmpty) ...[
            Text('Conditions', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.diseases
                  .map((d) => Chip(
                        label: Text(d),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              _AlertPill(icon: Icons.cloud_outlined, label: 'Pollution', active: item.alerts.pollution),
              const SizedBox(width: 8),
              _AlertPill(icon: Icons.volume_up_outlined, label: 'Sound', active: item.alerts.sound),
              const SizedBox(width: 8),
              if (item.receivedAt != null)
                Flexible(
                  child: Text(
                    'Received: ${item.receivedAt!.toLocal()}'
                        .replaceFirst(RegExp(r'\.\d+'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                ),
            ],
          ),

          if (item.alerts.hours2h.isNotEmpty) ...[
            const SizedBox(height: 8),
            _HoursRow(hours: item.alerts.hours2h),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onForecastNow,
                  icon: const Icon(Icons.timeline),
                  label: const Text('Forecast now'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: (onConfirmAndDelete == null || isDeleting)
                      ? null
                      : () async {
                          final confirmed = await _confirmDelete(context, name: item.name);
                          if (confirmed) {
                            final ok = await onConfirmAndDelete!.call();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Deleted successfully' : 'Delete failed'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  icon: isDeleting
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, {required String name}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete record?'),
            content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }
}

class _AlertPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _AlertPill({required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    final color = active ? base : Theme.of(context).hintColor;
    final bg = color.withOpacity(active ? 0.10 : 0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _HoursRow extends StatelessWidget {
  final List<int> hours;
  const _HoursRow({required this.hours});

  String _h(int h) {
    final hh = h % 24;
    final am = hh < 12;
    final base = (hh % 12 == 0) ? 12 : hh % 12;
    return '$base ${am ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).hintColor,
          fontWeight: FontWeight.w600,
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.schedule, size: 16),
        Text('Hours:', style: textStyle),
        ...hours.map((h) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_h(h), style: textStyle),
            )),
      ],
    );
  }
}
