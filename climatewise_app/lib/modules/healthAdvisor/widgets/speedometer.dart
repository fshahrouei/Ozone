// lib/modules/healthAdvisor/widgets/health_form/speedometer.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

class SpeedometerGauge extends StatelessWidget {
  final double value0to100;
  final String label;
  final Color color;
  final double maxHeight;
  final Duration duration;

  const SpeedometerGauge({
    super.key,
    required this.value0to100,
    required this.label,
    required this.color,
    this.maxHeight = 220,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  Widget build(BuildContext context) {
    final double target = value0to100.clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: 2,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: target, end: target),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) {
                  return CustomPaint(
                    painter: _TopHalfSpeedometerPainter(
                      value0to100: animated,
                      needleColor: color,
                      arcBg: Colors.grey.shade200,
                      green: const Color(0xFF2E7D32),
                      yellow: const Color(0xFFF9A825),
                      red: const Color(0xFFC62828),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: target, end: target),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              '${v.toStringAsFixed(0)}/100',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }
}

class _TopHalfSpeedometerPainter extends CustomPainter {
  final double value0to100;
  final Color needleColor;
  final Color arcBg; final Color green; final Color yellow; final Color red;

  _TopHalfSpeedometerPainter({
    required this.value0to100,
    required this.needleColor,
    required this.arcBg,
    required this.green,
    required this.yellow,
    required this.red,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const stroke = 16.0, tickBig = 10.0, tickSmall = 6.0;
    final margin = stroke/2 + tickBig + 10;
    final center = Offset(w/2, h - margin);
    final radius = math.max(0.0, math.min(w/2 - margin, h - margin));
    final rect = Rect.fromCircle(center: center, radius: radius);

    const startAngle = 0.0;
    const sweepAngle = -math.pi;

    Paint ring(Color c)=>Paint()..color=c..strokeWidth=stroke..style=PaintingStyle.stroke;

    canvas.drawArc(rect, startAngle, sweepAngle, false, ring(arcBg));
    const t1=33.0/100.0, t2=66.0/100.0;
    canvas.drawArc(rect, startAngle, sweepAngle*t1, false, ring(green));
    canvas.drawArc(rect, startAngle + sweepAngle*t1, sweepAngle*(t2-t1), false, ring(yellow));
    canvas.drawArc(rect, startAngle + sweepAngle*t2, sweepAngle*(1-t2), false, ring(red));

    final tickPaint = Paint()..color=Colors.grey.shade600..strokeWidth=2;
    for (int i=0;i<=10;i++){
      final t=i/10.0, ang=startAngle + sweepAngle*t;
      final outer=Offset(center.dx + radius*math.cos(ang), center.dy + radius*math.sin(ang));
      final innerLen = (i%2==0)?tickBig:tickSmall;
      final inner=Offset(center.dx + (radius-innerLen)*math.cos(ang), center.dy + (radius-innerLen)*math.sin(ang));
      canvas.drawLine(inner, outer, tickPaint);
    }

    final frac=(value0to100/100.0).clamp(0.0,1.0);
    final needleAngle=startAngle + sweepAngle*frac;
    final needleLen = radius - (stroke+8);
    final needleEnd=Offset(center.dx + needleLen*math.cos(needleAngle), center.dy + needleLen*math.sin(needleAngle));
    canvas.drawLine(center, needleEnd, Paint()..color=needleColor..strokeWidth=3.8..style=PaintingStyle.stroke);
    canvas.drawCircle(center, 4.5, Paint()..color=Colors.black87);
  }

  @override
  bool shouldRepaint(covariant _TopHalfSpeedometerPainter o) =>
    o.value0to100!=value0to100 || o.needleColor!=needleColor || o.arcBg!=arcBg || o.green!=green || o.yellow!=yellow || o.red!=red;
}
