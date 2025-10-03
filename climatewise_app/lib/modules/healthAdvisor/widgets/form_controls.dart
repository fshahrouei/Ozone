// lib/modules/healthAdvisor/widgets/health_form/form_controls.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/tabs/health_form_tab.dart' show Sensitivity;

/// Section title (shared)
Widget sectionTitle(String t) => Text(
  t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .2),
);

// Name field
class NameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? serverErrorText;
  const NameField({super.key, required this.controller, this.focusNode, this.serverErrorText});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: (v)=> (v==null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        errorText: serverErrorText,
        labelText: 'Full name',
        filled: true, fillColor: Colors.blue.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blueGrey.shade100)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blueGrey.shade100)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.blue, width: 1.5)),
      ),
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_)=> FocusScope.of(context).unfocus(),
    );
  }
}

// Sensitivity segmented control
class SensitivitySegment extends StatelessWidget {
  final Sensitivity value;
  final ValueChanged<Sensitivity> onChanged;
  const SensitivitySegment({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = {
      Sensitivity.sensitive: 'Sensitive',
      Sensitivity.normal: 'Normal',
      Sensitivity.relaxed: 'Relaxed',
    };
    return Row(
      children: items.entries.map((e) {
        final selected = e.key == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: ()=> onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? Colors.blue : Colors.blue.shade50,
                  border: Border.all(color: selected ? Colors.blue : Colors.blueGrey.shade100),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(e.value, style: TextStyle(color: selected?Colors.white:Colors.black87, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Lat/Lon row + pills
class LatLonRow extends StatelessWidget {
  final LatLng latLng;
  const LatLonRow({super.key, required this.latLng});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _CoordPill(label:'Lat', value: latLng.latitude.toStringAsFixed(5))),
      const SizedBox(width: 8),
      Expanded(child: _CoordPill(label:'Lon', value: latLng.longitude.toStringAsFixed(5))),
    ]);
  }
}

class _CoordPill extends StatelessWidget {
  final String label; final String value;
  const _CoordPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.blueGrey.shade700)),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
