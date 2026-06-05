import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'theme.dart';

const String _kPoofAsset = 'assets/poof.json';

/// 可删除胶囊（用于别名等简单标签列表）：
/// - 正常：显示文字，点击可触发 onTap（可选）
/// - 长按：进入"待删"态——变灰 + 持续抖动（仿 iOS 编辑）
/// - 待删态双击：播 poof 烟雾后回调 onDeleted
/// - 待删态再次长按/点击别处不处理；点自身以外由父级管理退出（这里点自身切回正常）
class ShakeDeletableCapsule extends StatefulWidget {
  final String label;
  final int colorIdx;
  final VoidCallback onDeleted;
  final VoidCallback? onDeleteStart; // 开始删除（poof 起播）时通知父级
  final VoidCallback? onTap;
  const ShakeDeletableCapsule({
    super.key,
    required this.label,
    required this.colorIdx,
    required this.onDeleted,
    this.onDeleteStart,
    this.onTap,
  });
  @override
  State<ShakeDeletableCapsule> createState() => _ShakeDeletableCapsuleState();
}

class _ShakeDeletableCapsuleState extends State<ShakeDeletableCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
  bool _arming = false; // 待删态（变灰+抖动）
  bool _poofing = false; // 正在播放销毁烟雾（淡出）
  bool _collapsed = false; // poof 后收缩宽度（让 + 平滑挤过来）
  late final double _phase = (widget.label.hashCode % 100) / 100.0;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _enterArm() {
    HapticFeedback.mediumImpact();
    setState(() => _arming = true);
    _shake.repeat(reverse: true);
  }

  void _exitArm() {
    setState(() => _arming = false);
    _shake.stop();
    _shake.reset();
  }

  void _destroy() {
    if (_poofing) return;
    setState(() {
      _poofing = true; // 立即淡出（保留尺寸占位，+ 不立刻移过来）
      _arming = false;
    });
    _shake.stop();
    widget.onDeleteStart?.call(); // 通知父级：删除中（+ 不可选中）
    // 在胶囊当前屏幕位置插入一层 Overlay 播放 poof（脱离布局，跟随实际中心）
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context, rootOverlay: true);
    if (box != null) {
      final topLeft = box.localToGlobal(Offset.zero);
      final center = topLeft + Offset(box.size.width / 2, box.size.height / 2);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: center.dx - 45,
          top: center.dy - 45,
          width: 90,
          height: 90,
          child: IgnorePointer(
            child: Lottie.asset(_kPoofAsset, repeat: false),
          ),
        ),
      );
      overlay.insert(entry);
      Future.delayed(const Duration(milliseconds: 700), () {
        entry.remove();
      });
    }
    // poof 播完 → 收缩宽度（AnimatedSize 让 + 平滑挤过来）
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _collapsed = true);
    });
    // 收缩动画结束后真正移除
    Future.delayed(const Duration(milliseconds: 700 + 260), () {
      if (mounted) widget.onDeleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = _arming
        ? Colors.grey.shade400
        : Style_C.bg(widget.colorIdx);
    final ink = _arming ? Colors.white : Style_C.ink(widget.colorIdx);

    Widget capsule = Container(
      constraints: const BoxConstraints(minWidth: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        widget.label,
        style: TextStyle(
            color: ink, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    // 待删态：抖动
    if (_arming) {
      capsule = AnimatedBuilder(
        animation: _shake,
        builder: (_, child) {
          final angle = sin((_shake.value + _phase) * pi * 2) * 0.04;
          return Transform.rotate(angle: angle, child: child);
        },
        child: capsule,
      );
    }

    return GestureDetector(
      onTap: () {
        if (_arming) {
          _exitArm(); // 待删态下点自身 → 退出待删
        } else {
          widget.onTap?.call();
        }
      },
      onLongPress: _arming ? null : _enterArm,
      onDoubleTap: _arming ? _destroy : null,
      // 删除过渡：先淡出（poof 起播），poof 后宽度收缩到 0 → + 平滑挤过来
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: Alignment.centerLeft,
        child: _collapsed
            ? const SizedBox(height: 0, width: 0)
            : AnimatedOpacity(
                opacity: _poofing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: capsule,
              ),
      ),
    );
  }
}