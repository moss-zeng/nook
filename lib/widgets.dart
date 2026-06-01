import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'smb/smb_client.dart';

/// 浅蓝圆角方块按钮
class SoftSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const SoftSquareButton({super.key, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.accentSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: C.ink, size: 24),
        ),
      ),
    );
  }
}

/// 内存级封面缓存：key=SMB 路径，value=字节(或 null 表示已查无)
class CoverCache {
  static final Map<String, Uint8List?> _mem = {};

  // 并发闸：同时最多 2 个 SMB 读图，其余排队，避免打爆 Windows 连接数
  static const int _maxConcurrent = 2;
  static int _active = 0;
  static final List<Completer<void>> _queue = [];

  static Future<void> _acquire() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _active++;
  }

  static void _release() {
    _active--;
    if (_queue.isNotEmpty) {
      final c = _queue.removeAt(0);
      c.complete();
    }
  }

  /// 依次尝试多个候选路径，返回第一个读到的图片字节；都没有返回 null。
  static Future<Uint8List?> load(SmbCreds c, List<String> candidates) async {
    final cacheKey = candidates.join('|');
    if (_mem.containsKey(cacheKey)) return _mem[cacheKey];

    await _acquire();
    Uint8List? found;
    try {
      for (final p in candidates) {
        try {
          final bytes = await SmbClient.readImage(c, p);
          if (bytes != null && bytes.isNotEmpty) {
            found = bytes;
            break;
          }
        } catch (_) {
          // 单个候选失败，继续
        }
      }
    } finally {
      _release();
    }
    _mem[cacheKey] = found;
    return found;
  }
}

/// 异步封面图：读不到则回退到"白底 + 蓝字名称"
class CoverImage extends StatefulWidget {
  final SmbCreds creds;
  final List<String> candidates; // 按优先级排列的封面路径
  final String fallbackName; // 没图时显示的名字
  final double? aspectRatioFallback; // 没图时占位的宽高比（默认 1）
  final BoxFit fit;
  const CoverImage({
    super.key,
    required this.creds,
    required this.candidates,
    required this.fallbackName,
    this.aspectRatioFallback,
    this.fit = BoxFit.cover,
  });
  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  Uint8List? _bytes;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverImage old) {
    super.didUpdateWidget(old);
    if (old.candidates.join('|') != widget.candidates.join('|')) {
      _done = false;
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final b = await CoverCache.load(widget.creds, widget.candidates);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit);
    }
    // 占位 / 回退：白底蓝字名
    final placeholder = Container(
      color: C.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        widget.fallbackName,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: C.accent, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
    if (!_done) {
      // 加载中也先占位（避免闪烁），用一个比例盒子撑住
      return AspectRatio(
        aspectRatio: widget.aspectRatioFallback ?? 1,
        child: Container(color: C.bg),
      );
    }
    if (widget.aspectRatioFallback != null) {
      return AspectRatio(
          aspectRatio: widget.aspectRatioFallback!, child: placeholder);
    }
    return placeholder;
  }
}
