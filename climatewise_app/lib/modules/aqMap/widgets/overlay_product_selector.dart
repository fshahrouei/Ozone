// lib/modules/aqMap/widgets/overlay_product_selector.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/aq_map_controller.dart';

class OverlayProductSelector extends StatelessWidget {
  const OverlayProductSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AqMapController>();
    final String selectedKey = c.overlayOn ? c.product : 'off';

    final options = <_Opt>[
      const _Opt(key: 'off',  label: 'OFF',    enabled: true),
      const _Opt(key: 'no2',  label: 'NO₂',    enabled: true),
      const _Opt(key: 'hcho', label: 'HCHO',   enabled: true),
      const _Opt(key: 'o3tot',label: 'O₃',     enabled: true),
      const _Opt(key: 'cldo4',label: 'Clouds', enabled: true),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 1), // margin-bottom like CSS
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7), // semi-transparent "glass" look
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black26.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < options.length; i++) ...[
              Expanded(
                child: _ProductButton(
                  option: options[i],
                  isSelected: options[i].key == selectedKey,
                  onTap: options[i].enabled
                      ? () {
                          final ctrl = context.read<AqMapController>();
                          if (options[i].key == 'off') {
                            ctrl.setOverlayOn(false);
                          } else {
                            ctrl.setOverlayOn(true);
                            ctrl.setProduct(options[i].key);
                          }
                        }
                      : null,
                ),
              ),
              if (i != options.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductButton extends StatelessWidget {
  final _Opt option;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ProductButton({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = !option.enabled;
    final Color bg = isSelected ? Colors.black : Colors.white.withOpacity(0.8);
    final Color fg = isSelected ? Colors.white : Colors.black87;
    final Color border = disabled ? Colors.black12 : Colors.black26;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: disabled ? Colors.white.withOpacity(0.5) : bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: disabled ? Colors.black38 : fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );

    return disabled
        ? Tooltip(
            message: 'Clouds is coming soon',
            child: Opacity(opacity: 0.7, child: btn),
          )
        : btn;
  }
}

class _Opt {
  final String key;
  final String label;
  final bool enabled;
  const _Opt({required this.key, required this.label, required this.enabled});
}
