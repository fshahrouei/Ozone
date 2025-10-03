// lib/modules/healthAdvisor/widgets/health_form/alerts_widgets.dart
import 'package:flutter/material.dart';

class AlertSwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const AlertSwitchRow({super.key, required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Switch(value: value, onChanged: onChanged),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class AlertsTwoHourGroup extends StatelessWidget {
  final Set<int> selected; // 0..23 step 2
  final int maxSelections;
  final String Function(int hour24) formatHourLabel;
  final void Function(int hour24) onToggle;

  const AlertsTwoHourGroup({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.formatHourLabel,
    this.maxSelections = 5,
  });

  @override
  Widget build(BuildContext context) {
    final isAtLimit = selected.length >= maxSelections;
    final slots = List.generate(12, (i)=> (i*2)%24); // 0,2,...,22

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Periodic level notifications', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: slots.map((h) {
              final isSelected = selected.contains(h);
              final isDisabled = !isSelected && isAtLimit;
              return ChoiceChip(
                label: Text(formatHourLabel(h)),
                selected: isSelected,
                onSelected: isDisabled ? null : (_)=>onToggle(h),
                selectedColor: Colors.blue,
                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
