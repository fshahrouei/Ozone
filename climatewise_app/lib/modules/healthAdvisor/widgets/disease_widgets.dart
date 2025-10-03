// lib/modules/healthAdvisor/widgets/health_form/disease_widgets.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class DiseaseSpec {
  final String id;
  final String name;
  final Map<String, double> weights; // product -> weight (0..1)
  const DiseaseSpec({required this.id, required this.name, required this.weights});
}

class RiskChipCard extends StatelessWidget {
  final String title;
  final int risk0to100;
  final bool selected;
  final ValueChanged<bool?>? onChanged; // null → disabled
  final Color color;
  final bool enabled;

  const RiskChipCard({
    super.key,
    required this.title,
    required this.risk0to100,
    required this.selected,
    required this.onChanged,
    required this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final double frac = (risk0to100 / 100).clamp(0.0, 1.0).toDouble();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected && enabled ? color.withOpacity(0.7) : Colors.black12,
          width: selected && enabled ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: onChanged),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          SizedBox(
            width: 42, height: 42,
            child: _AnimatedMiniPieChart(fraction: frac, color: color, label: risk0to100.toString()),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMiniPieChart extends StatelessWidget {
  final double fraction; // 0..1
  final Color color;
  final String label;
  final Duration duration;
  const _AnimatedMiniPieChart({
    required this.fraction,
    required this.color,
    required this.label,
    this.duration = const Duration(milliseconds: 450),
  });

  @override
  Widget build(BuildContext context) {
    final target = fraction.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => _MiniPieChart(fraction: v, color: color, label: label),
    );
  }
}

class _MiniPieChart extends StatelessWidget {
  final double fraction; final Color color; final String label;
  const _MiniPieChart({required this.fraction, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0).toDouble();
    return Stack(
      children: [
        PieChart(PieChartData(
          startDegreeOffset: -90, sectionsSpace: 0, centerSpaceRadius: 16,
          sections: [
            PieChartSectionData(value: f, color: color, radius: 12, showTitle: false),
            PieChartSectionData(value: 1-f, color: Colors.grey.shade300, radius: 12, showTitle: false),
          ],
        )),
        Center(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
      ],
    );
  }
}
