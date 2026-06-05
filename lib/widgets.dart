import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'smb/smb_client.dart';

/// 封面文件名固定为 _cover，后缀支持常见图片格式（按优先级排列）。
/// 给定人物/作品目录，返回一组候选封面路径，CoverImage 会取第一个能读到的。
const List<String> _coverExts = [
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'avif'
];
List<String> coverCandidates(String basePath) =>
    [for (final e in _coverExts) '$basePath/_cover.$e'];

/// 作品封面候选：作品自有封面（.covers/作品名.扩展名，尝试多扩展名 + 原文件名大小写变体），
/// 找不到再退到人物封面 _cover.*。三处（person_page/keep/cover_index）统一用它，
/// 保证扩展名/大小写不匹配时也能命中（封面常是 .webp，文件名可能含 .MP4 大写）。
List<String> workCoverCandidates(String ownerPath, String fileName) {
  final dir = '$ownerPath/.covers';
  // 原文件名 + 扩展名大小写变体（如 xxx.MP4 / xxx.mp4），去重保序
  final nameVariants = <String>{
    fileName,
    fileName.toLowerCase(),
    fileName.toUpperCase(),
  }.toList();
  final out = <String>[];
  for (final nm in nameVariants) {
    for (final e in _coverExts) {
      out.add('$dir/$nm.$e');
    }
  }
  // 作品自有封面优先，其次人物封面
  out.addAll(coverCandidates(ownerPath));
  return out;
}

/// 内存级封面缓存：key=SMB 路径，value=字节(或 null 表示已查无)
class CoverCache {
  static final Map<String, Uint8List?> _mem = {};

  /// 清空全部封面缓存（换 share / 重建索引后调用，让换过的封面重新从 SMB 读）。
  static void clearAll() => _mem.clear();

  /// 按路径前缀清除（如某人物目录下的所有封面）。
  static void clearPrefix(String prefix) {
    _mem.removeWhere((key, _) => key.contains(prefix));
  }

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

/// 异步封面图。读不到时的回退：
/// - 提供 fallbackColorIdx → 用 Style_C 该色号的色块 + 名字（融入 View 配色链）
/// - 未提供但有 fallbackName → 按名字 hash 自动取 Style_C 色块 + 名字
/// - fallbackName 为空 → 中性占位（不显示名字、不彩色，用于图库/大背景等场景）
class CoverImage extends StatefulWidget {
  final SmbCreds creds;
  final List<String> candidates; // 按优先级排列的封面路径
  final String fallbackName; // 没图时显示的名字（空 = 中性占位）
  final int? fallbackColorIdx; // 没图时的色号（1~20）；为空则按 fallbackName hash
  final Color? fallbackColor; // 没图时的纯色占位（优先于色号；供非 Style_C 配色链如 Keep 用）
  final Color? fallbackInk; // 纯色占位上的文字色（配合 fallbackColor）
  final double? aspectRatioFallback; // 没图时占位的宽高比（默认 1）
  final double? knownAspectRatio; // 已知封面真实宽高比（来自 cover_index）：加载前后高度一致，瀑布流不跳
  final BoxFit fit;
  final ValueChanged<bool>? onResolved; // 解析完成回调：true=拿到封面，false=回退
  const CoverImage({
    super.key,
    required this.creds,
    required this.candidates,
    required this.fallbackName,
    this.fallbackColorIdx,
    this.fallbackColor,
    this.fallbackInk,
    this.aspectRatioFallback,
    this.knownAspectRatio,
    this.fit = BoxFit.cover,
    this.onResolved,
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
    widget.onResolved?.call(b != null);
  }

  @override
  Widget build(BuildContext context) {
    // 已知真实比例：加载前后都用它锁高度，瀑布流零重排
    final known = widget.knownAspectRatio;

    if (_bytes != null) {
      final img = Image.memory(_bytes!, fit: widget.fit);
      // 有已知比例 → 锁定（与占位同高，不跳）；否则按图片自身比例
      return known != null
          ? AspectRatio(aspectRatio: known, child: img)
          : img;
    }

    final hasName = widget.fallbackName.trim().isNotEmpty;
    // 色号：显式优先；否则按名字 hash；名字为空则无彩色
    final colorIdx = widget.fallbackColorIdx ??
        (hasName ? Style_C.idxOf(widget.fallbackName) : null);

    // 回退占位
    final Widget placeholder;
    if (widget.fallbackColor != null) {
      // 纯色占位（如 Keep_C），文字用 fallbackInk
      final ink = widget.fallbackInk ?? Colors.white;
      placeholder = Container(
        color: widget.fallbackColor,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: hasName
            ? Text(
                widget.fallbackName,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: ink, fontSize: 14, fontWeight: FontWeight.w600),
              )
            : const SizedBox.shrink(),
      );
    } else if (colorIdx != null) {
      // Style_C 色块 + 名字（无名时纯色块）
      placeholder = Container(
        color: Style_C.bg(colorIdx),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: hasName
            ? Text(
                widget.fallbackName,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Style_C.ink(colorIdx),
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              )
            : const SizedBox.shrink(),
      );
    } else {
      // 中性占位（图库/大背景等无名场景）
      placeholder = Container(color: View_C.surface);
    }

    // 占位的比例：优先已知比例 → 其次 fallback → 默认 1
    final placeholderAr = known ?? widget.aspectRatioFallback;

    if (!_done) {
      // 加载中也先占位（避免闪烁），用比例盒子撑住（优先已知比例）
      return AspectRatio(
        aspectRatio: placeholderAr ?? 1,
        child: Container(color: View_C.bg),
      );
    }
    if (placeholderAr != null) {
      return AspectRatio(aspectRatio: placeholderAr, child: placeholder);
    }
    return placeholder;
  }
}