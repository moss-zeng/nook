import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'models/person_meta.dart';
import 'theme.dart';

/// Love 三态显示/编辑控件：空心 -> 红心 -> 火焰爱心
/// - 仅显示用：interactive=false
/// - 可编辑：interactive=true，点击循环并回调
///
/// 爱心本体由 CustomPainter 自绘（含空心/粉心/火焰静态三态 + 点击变大变小）。
/// 切换时的爆发特效改为叠加 Lottie：
///   1->2 播 assets/fx_1to2.json
///   2->3 播 assets/fx_2to3.json
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

class _LoveBadgeState extends State<LoveBadge> with TickerProviderStateMixin {
  late AnimationController _pop; // 心跳/变大变小动画
  late AnimationController _fx1; // 1->2 特效（Lottie）
  late AnimationController _fx2; // 2->3 特效（Lottie）

  // 控制两个特效层显示与否：播完后藏起来，避免残留最后一帧
  bool _showFx1 = false;
  bool _showFx2 = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    // 时长在 Lottie onLoaded 时用动画自带时长覆盖
    _fx1 = AnimationController(vsync: this);
    _fx2 = AnimationController(vsync: this);

    AssetLottie('assets/fx_1to2.json').load().then((c) {
      if (mounted) _fx1.duration = c.duration;
    });
    AssetLottie('assets/fx_2to3.json').load().then((c) {
      if (mounted) _fx2.duration = c.duration;
    });

    // 播完自动隐藏对应特效层
    _fx1.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showFx1 = false);
      }
    });
    _fx2.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showFx2 = false);
      }
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    _fx1.dispose();
    _fx2.dispose();
    super.dispose();
  }

  void _cycle() {
    if (!widget.interactive) return;
    final cur = widget.love;
    final next = switch (cur) {
      Love.passable => Love.preferred, // 1->2
      Love.preferred => Love.pinnacle, // 2->3
      Love.pinnacle => Love.passable, // 3->1
    };

    _pop.forward(from: 0); // 变大变小始终触发

    // 按"从哪到哪"决定放哪个特效
    if (cur == Love.passable && next == Love.preferred) {
      setState(() => _showFx1 = true);
      _fx1.duration ??= const Duration(milliseconds: 600); // 兜底，防止还没加载完
      _fx1.forward(from: 0);
    } else if (cur == Love.preferred && next == Love.pinnacle) {
      setState(() => _showFx2 = true);
      _fx2.duration ??= const Duration(milliseconds: 600); // 兜底，防止还没加载完
      _fx2.forward(from: 0);
    }

    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    // 特效层比爱心大一圈，飞散的火星/碎片才不会被裁掉
    final fxSize = widget.size * 2.2;

    return GestureDetector(
      onTap: widget.interactive ? _cycle : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // ① 底层：自绘爱心 + pop 跳动
            AnimatedBuilder(
              animation: _pop,
              builder: (_, __) {
                final pop = 1.0 +
                    0.25 *
                        Curves.easeOut.transform(
                            (_pop.isAnimating ? (1 - (_pop.value - 0.5).abs() * 2) : 0.0)
                                .clamp(0.0, 1.0));
                return SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CustomPaint(
                    painter: _LovePainter(love: widget.love, pop: pop),
                  ),
                );
              },
            ),

            // ② 特效层：1->2（不拦截点击）
            if (_showFx1)
              Positioned.fill(
                child: IgnorePointer(
                  child: OverflowBox(
                    maxWidth: fxSize,
                    maxHeight: fxSize,
                    child: Lottie.asset(
                      'assets/fx_1to2.json',
                      controller: _fx1,
                      fit: BoxFit.contain,
                      onLoaded: (composition) {
                        _fx1.duration = composition.duration;
                      },
                    ),
                  ),
                ),
              ),
            // ③ 特效层：2->3（不拦截点击）
            if (_showFx2)
              Positioned.fill(
                child: IgnorePointer(
                  child: OverflowBox(
                    maxWidth: fxSize,
                    maxHeight: fxSize,
                    child: Lottie.asset(
                      'assets/fx_2to3.json',
                      controller: _fx2,
                      fit: BoxFit.contain,
                      onLoaded: (composition) {
                        _fx2.duration = composition.duration;
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LovePainter extends CustomPainter {
  final Love love;
  final double pop; // 缩放
  _LovePainter({required this.love, required this.pop});

  Path _heartPath(Size size) {
    final w = size.width*0.85;
    final h = size.height;
    final path = Path();

    // 底部尖点
    path.moveTo(w * 0.5, h * 0.92);

    // 左下
    path.cubicTo(
      w * 0.35, h * 0.78,
      w * 0.02, h * 0.62,
      w * 0.02, h * 0.42,
    );
    // 左上
    path.cubicTo(
      w * 0.02, h * 0.18,
      w * 0.30, h * 0.08,
      w * 0.5, h * 0.30,
    );

    // 右上
    path.cubicTo(
      w * 0.70, h * 0.08,
      w * 0.98, h * 0.18,
      w * 0.98, h * 0.42,
    );
    // 右下
    path.cubicTo(
      w * 0.98, h * 0.62,
      w * 0.65, h * 0.78,
      w * 0.5, h * 0.92,
    );

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // 缩放跳动动画
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(pop);
    canvas.translate(-size.width / 2, -size.height / 2);

    final heartPath = _heartPath(size);

    switch (love) {
      case Love.passable:
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.045
          ..color = Heart_C.stroke;
        canvas.drawPath(heartPath, paint);
        break;

      case Love.preferred:
        _drawSoftPinkHeart(canvas, size, heartPath);
        break;

      case Love.pinnacle:
        _drawFlameHeart(canvas, size, heartPath);
        break;
    }

    canvas.restore();
  }

  /// 低饱和渐变粉心（激活态）
  void _drawSoftPinkHeart(Canvas canvas, Size size, Path heartPath) {
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.5,
      colors: const [
        Heart_C.pinkStart,
        Heart_C.pinkEnd,
      ],
    );
    final paint = Paint()
      ..shader =
          gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(heartPath, paint);
  }

  /// 火焰配色静态爱心（顶点态）
  void _drawFlameHeart(Canvas canvas, Size size, Path heartPath) {
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.42,
      colors: const [
        Heart_C.flameInner,
        Heart_C.flameMid,
        Heart_C.flameOuter,
      ],
      stops: const [0.0, 0.6, 1.0],
    );
    final paint = Paint()
      ..shader =
          gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(heartPath, paint);
  }

  @override
  bool shouldRepaint(covariant _LovePainter old) =>
      old.love != love || old.pop != pop;
}