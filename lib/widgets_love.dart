import 'package:flutter/material.dart';
import 'models/person_meta.dart';
import 'theme.dart';

/// Love 三态显示/编辑控件：空心 -> 红心 -> 红心带火焰
/// - 仅显示用：interactive=false
/// - 可编辑：interactive=true，点击循环并回调
class LoveBadge extends StatefulWidget {
  final Love love;
  final bool interactive;
  final double size;
  final ValueChanged<Love>? onChanged;
  const LoveBadge({
    super.key,
    required this.love,
    this.interactive = false,
    this.size = 24,
    this.onChanged,
  });
  @override
  State<LoveBadge> createState() => _LoveBadgeState();
}

class _LoveBadgeState extends State<LoveBadge>
    with TickerProviderStateMixin {
  late AnimationController _pop; // 心跳动画
  late AnimationController _flame; // 火焰持续动画

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _flame = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _updateFlame();
  }

  void _updateFlame() {
    if (widget.love == Love.pinnacle) {
      if (!_flame.isAnimating) _flame.repeat();
    } else {
      if (_flame.isAnimating) _flame.stop();
    }
  }

  @override
  void didUpdateWidget(LoveBadge old) {
    super.didUpdateWidget(old);
    _updateFlame();
  }

  @override
  void dispose() {
    _pop.dispose();
    _flame.dispose();
    super.dispose();
  }

  void _cycle() {
    if (!widget.interactive) return;
    final next = switch (widget.love) {
      Love.passable => Love.preferred,
      Love.preferred => Love.pinnacle,
      Love.pinnacle => Love.passable,
    };
    _pop.forward(from: 0);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.interactive ? _cycle : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pop, _flame]),
        builder: (_, __) {
          final pop = 1.0 + 0.25 * Curves.easeOut.transform(
              (_pop.isAnimating ? (1 - (_pop.value - 0.5).abs() * 2) : 0.0)
                  .clamp(0.0, 1.0));
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _LovePainter(
                love: widget.love,
                flameT: _flame.value,
                pop: pop,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LovePainter extends CustomPainter {
  final Love love;
  final double flameT; // 0..1 循环
  final double pop; // 缩放
  _LovePainter({required this.love, required this.flameT, required this.pop});

  Path _heartPath(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // 标准心形
    path.moveTo(w * 0.5, h * 0.85);
    path.cubicTo(w * 0.05, h * 0.55, w * 0.10, h * 0.18, w * 0.5, h * 0.40);
    path.cubicTo(w * 0.90, h * 0.18, w * 0.95, h * 0.55, w * 0.5, h * 0.85);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // 以中心缩放做 pop
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(pop);
    canvas.translate(-size.width / 2, -size.height / 2);

    final heart = _heartPath(size);

    if (love == Love.passable) {
      // 空心：描边
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.08
        ..color = C.inkSoft;
      canvas.drawPath(heart, stroke);
    } else {
      // 实心红心
      final fill = Paint()..color = const Color(0xFFE0395E);
      canvas.drawPath(heart, fill);

      if (love == Love.pinnacle) {
        // 顶部火焰
        _drawFlame(canvas, size);
      }
    }
    canvas.restore();
  }

  void _drawFlame(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 火焰在心形上方中央，随 flameT 轻微摆动/缩放
    final wobble = (flameT * 6.28);
    final sway = 0.04 * w * (1 + 0.3) *
        (0.5 - (flameT - 0.5).abs()) * 2; // 简单上下脉动因子
    final cx = w * 0.5 + 0.02 * w * (flameT < 0.5 ? 1 : -1);
    final baseY = h * 0.30;
    final tipY = baseY - h * (0.22 + 0.05 * (0.5 - (flameT - 0.5).abs()) * 2);

    final outer = Path()
      ..moveTo(cx - w * 0.10, baseY)
      ..quadraticBezierTo(cx - w * 0.13, (baseY + tipY) / 2, cx, tipY)
      ..quadraticBezierTo(cx + w * 0.13, (baseY + tipY) / 2, cx + w * 0.10, baseY)
      ..quadraticBezierTo(cx, baseY + h * 0.04, cx - w * 0.10, baseY)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFFFF8A1E));

    // 内焰
    final inner = Path()
      ..moveTo(cx - w * 0.05, baseY - h * 0.02)
      ..quadraticBezierTo(
          cx - w * 0.06, (baseY + tipY) / 2, cx, tipY + h * 0.06)
      ..quadraticBezierTo(
          cx + w * 0.06, (baseY + tipY) / 2, cx + w * 0.05, baseY - h * 0.02)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD23E));
  }

  @override
  bool shouldRepaint(covariant _LovePainter old) =>
      old.love != love || old.flameT != flameT || old.pop != pop;
}
