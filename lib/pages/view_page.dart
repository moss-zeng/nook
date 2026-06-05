import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme.dart';
import '../widgets.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../models/styles.dart';
import 'people_page.dart';
import 'text_page.dart';
import 'gallery_page.dart';

// ============ 暴露给 shell：风格库是否已"开箱完成"（控制搜索按钮出现时机）============
// viewSceneReadyProvider 定义在 state/connection.dart（与 isStyleLibraryProvider 同款），
// 这里直接 import 使用：ref.read(viewSceneReadyProvider.notifier).set(true/false)

// ============ 可调参数（动画 / 散布 / 资源）—— 按需微调 ============
const String kBoxAsset = 'assets/box_open.json';   // idle 循环 + open 一体
const String kBurstAsset = 'assets/box_burst.json'; // 迸发叠加层

const int kMaxGroups = 20;        // 风格组上限；满 20 时不再出 + 胶囊
const double kIdleEnd = 0.45;     // box_open 中 idle/open 的分界（占整段比例）。
                                  // [0, kIdleEnd] 循环待机；[kIdleEnd, 1] 为打开段。
const Duration kBoxStartDelay = Duration(milliseconds: 100); // 盖过顶栏 520ms 切换动画后才起播 idle
const Duration kFlyDuration = Duration(milliseconds: 720);   // 胶囊炸开飞行时长（先快后慢 easeOutCubic）

const double kBoxSize = 200;          // 盒子显示尺寸
const double kCapsuleMaxWidth = 140;  // 组胶囊最大宽（名字超长截断）
const double kCapsuleHeight = 42;
const double kFootprintW = 140;       // 散布占位足迹（保证不同名字也不重叠）
const double kFootprintH = 56;
const double kGap = 12;               // 足迹之间最小间距
const double kTopPad = 56;            // 散布区上内边距（让出 inbox/blindbox 行）
const double kBottomPad = 110;        // 下内边距（让出底栏 + 搜索按钮）
const double kSidePad = 18;
const int kSampleTries = 120;         // 单点拒绝采样尝试次数（用户触发，主线程空闲，可放心多试）

const _videoExt = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'rmvb', 'rm'
};
bool _isVideo(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0) return false;
  return _videoExt.contains(name.substring(i + 1).toLowerCase());
}

bool _ignoredTop(String name) =>
    name.startsWith('_') || name.startsWith('.') || name == '_blindbox';

// 胶囊取色统一用 theme.dart 的 Style_C.bg(n)/ink(n)（n 从 1 开始，自动环绕）

class ViewPage extends ConsumerStatefulWidget {
  const ViewPage({super.key});
  @override
  ConsumerState<ViewPage> createState() => _ViewPageState();
}

class _ViewPageState extends ConsumerState<ViewPage> {
  String? _loadedShare;
  bool _loading = false;
  StylesConfig? _config;
  bool _resolved = false;

  @override
  Widget build(BuildContext context) {
    final share = ref.watch(selectedShareProvider);
    final conn = ref.watch(connectionProvider);
    // 仍 watch viewRefresh：盒子层据此感知"刚切进 View"以做帧安全（不再用作重建 key）
    ref.watch(viewRefreshProvider);

    if (share == null || conn.creds == null) {
      return const Center(
        child: Text('Pick a Share in Link',
            style: TextStyle(color: View_C.inkSoft, fontSize: 16)),
      );
    }

    if (_loadedShare != share && !_loading) {
      _loadedShare = share;
      _resolved = false;
      _loadMode(conn.creds!, share);
    }

    if (!_resolved) {
      return const Center(
          child: CircularProgressIndicator(color: View_C.accent));
    }

    if (_config != null) {
      // 关键：用 ValueKey('scene_$share') 而不是绑 refresh。
      // 同一 share 内（link↔view↔keep 切换、加/删组）State 保活、开箱状态留存；
      // 只有换 share 才换 key → 重建 → 回到盒子重新开箱。
      return _StyleScene(
        key: ValueKey('scene_$share'),
        creds: conn.creds!,
        share: share,
        config: _config!,
        onConfigChanged: (cfg) => setState(() => _config = cfg),
      );
    }

    // 普通 share（无 _styles.json）：退化成文件管理器，内嵌根目录浏览
    return _DirBrowser(
      creds: conn.creds!,
      dirPath: share,
      isInbox: false,
      isRoot: true,
    );
  }

  Future<void> _loadMode(SmbCreds c, String share) async {
    setState(() => _loading = true);
    CoverCache.clearAll(); // 换 share：清封面缓存，避免显示旧封面
    var cfg = await StylesRepo.load(c, share);
    // 同步校验：清理 _styles.json 里"磁盘已不存在"的幽灵风格项（电脑上改名/删除导致）
    if (cfg != null) {
      cfg = await _pruneGhostStyles(c, share, cfg);
    }
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _resolved = true;
      _loading = false;
    });
    ref.read(isStyleLibraryProvider.notifier).set(cfg != null);
    // 每次（重新）解析后，场景默认未就绪（盒子未开）。开箱完成由场景置 true。
    ref.read(viewSceneReadyProvider.notifier).set(false);
  }

  // 对照磁盘实际文件夹，剔除登记表中已不存在的风格名；有改动则写回 _styles.json
  Future<StylesConfig> _pruneGhostStyles(
      SmbCreds c, String share, StylesConfig cfg) async {
    Set<String> existing;
    try {
      final entries = await SmbClient.list(c, share);
      existing = entries.where((e) => e.isDir).map((e) => e.name).toSet();
    } catch (_) {
      return cfg; // 列目录失败：不动，避免误删
    }
    var changed = false;
    final newGroups = <StyleGroup>[];
    for (final g in cfg.groups) {
      final kept = g.styles.where(existing.contains).toList();
      if (kept.length != g.styles.length) changed = true;
      newGroups.add(StyleGroup(g.field, g.name, kept));
    }
    if (!changed) return cfg;
    final pruned = StylesConfig(newGroups);
    try {
      await StylesRepo.save(c, share, pruned); // 写回，幽灵项自此消失
    } catch (_) {}
    return pruned;
  }
}

// ============ 风格库场景：盒子 → 开箱 → 炸开散布 → 组胶囊 ============
enum _Stage { boxIdle, opening, scattering, ready }

// 销毁烟雾：记录播放位置（top-left，对齐被删胶囊的 slot）
class _Poof {
  final Offset boxTopLeft; // 烟雾框(120×120)左上角，已按胶囊中心算好
  _Poof(this.boxTopLeft);
}

const String kPoofAsset = 'assets/poof.json'; // 销毁烟雾（dotLottie 解压出的动画 json）

class _StyleScene extends ConsumerStatefulWidget {
  final SmbCreds creds;
  final String share;
  final StylesConfig config;
  final ValueChanged<StylesConfig> onConfigChanged;
  const _StyleScene({
    super.key,
    required this.creds,
    required this.share,
    required this.config,
    required this.onConfigChanged,
  });
  @override
  ConsumerState<_StyleScene> createState() => _StyleSceneState();
}

class _StyleSceneState extends ConsumerState<_StyleScene> {
  _Stage _stage = _Stage.boxIdle;
  final _rng = Random();

  // 散布点位池（top-left 坐标）。开箱时按需采样，删组释放、+/新组复用。
  final List<Offset> _slots = [];
  final Map<String, int> _groupSlot = {}; // field -> slot 索引（身份绑定，组不随列表位移）
  final Map<String, int> _groupColor = {}; // field -> 颜色序号 1..20
  int? _plusSlot; // + 胶囊所在 slot（= 空闲栈顶）；满 20 组或无空位时为 null
  bool _holdPlus = false; // poof 进行中：冻结 + 位置，等烟雾结束再释放点位

  Size? _area; // 最近一次散布区尺寸（LayoutBuilder 提供）
  bool _atCenter = false; // 胶囊是否处于"盒子中心"起飞前状态
  String? _greyField; // 当前"长按变灰待删"的空组 field（双击销毁）
  // 空闲 slot 栈（LIFO，后删先用）：删组时压入释放的 slot，+ 永远停在栈顶，
  // 点 + 时弹出栈顶给新组。解决一次删多个后 + 补位错乱。
  final List<int> _freeStack = [];
  _Poof? _poof; // 正在播放的销毁烟雾动画（位置 + 触发计数）
  Timer? _flyTimer;
  Timer? _poofTimer;
  Timer? _plusFlyTimer; // poof 70% 时让 + 起飞

  @override
  void initState() {
    super.initState();
    // 风格库不可移动文件，进入即清掉任何 pendingMove；并标记未就绪
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(pendingMoveProvider) != null) {
        ref.read(pendingMoveProvider.notifier).clear();
      }
      ref.read(viewSceneReadyProvider.notifier).set(false);
      ref.read(viewAccentProvider.notifier).set(null); // 第一层用默认色
    });
  }

  @override
  void didUpdateWidget(_StyleScene old) {
    super.didUpdateWidget(old);
    // config 变化（加/删组、改名、改风格）后，已就绪状态下重新对齐 slot/颜色占用
    if (_stage == _Stage.ready && _area != null) {
      setState(() => _reconcile(_area!));
    }
  }

  @override
  void dispose() {
    _flyTimer?.cancel();
    _poofTimer?.cancel();
    _plusFlyTimer?.cancel();
    super.dispose();
  }

  Rect _insetRect(Size a) =>
      Rect.fromLTRB(kSidePad, kTopPad, a.width - kSidePad, a.height - kBottomPad);

  Offset _centerTopLeft(Size a) {
    final r = _insetRect(a);
    return Offset(
        r.center.dx - kCapsuleMaxWidth / 2, r.center.dy - kCapsuleHeight / 2);
  }

  // 取一个 slot 给新组：优先弹出空闲栈顶（后删先用），否则采样新点位
  int _acquireSlot(Size area) {
    while (_freeStack.isNotEmpty) {
      final s = _freeStack.removeLast();
      // 跳过已被占用的（防御）
      if (!_groupSlot.values.contains(s) && s < _slots.length) return s;
    }
    _sampleNewSlot(area);
    return _slots.length - 1;
  }

  // 拒绝采样一个不与现有点位重叠的足迹位置；放不下时逐步放宽，最后尽力而为
  void _sampleNewSlot(Size area) {
    final r = _insetRect(area);
    final maxX = (r.right - kFootprintW);
    final maxY = (r.bottom - kFootprintH);
    final spanX = (maxX - r.left).clamp(0.0, double.infinity);
    final spanY = (maxY - r.top).clamp(0.0, double.infinity);
    Offset? best;
    var bestOverlap = 1 << 30;
    for (final gap in [kGap, kGap / 2, 0.0]) {
      for (var i = 0; i < kSampleTries; i++) {
        final x = r.left + _rng.nextDouble() * spanX;
        final y = r.top + _rng.nextDouble() * spanY;
        final cand = Rect.fromLTWH(x, y, kFootprintW, kFootprintH);
        var ov = 0;
        for (final s in _slots) {
          final sr = Rect.fromLTWH(s.dx, s.dy, kFootprintW, kFootprintH)
              .inflate(gap);
          if (sr.overlaps(cand)) ov++;
        }
        if (ov == 0) {
          _slots.add(Offset(x, y));
          return;
        }
        if (ov < bestOverlap) {
          bestOverlap = ov;
          best = Offset(x, y);
        }
      }
    }
    _slots.add(best ?? Offset(r.left, r.top));
  }

  int _pickColor() {
    final used = _groupColor.values.toSet();
    final avail = [for (var i = 1; i <= 20; i++) if (!used.contains(i)) i];
    if (avail.isEmpty) return _rng.nextInt(20) + 1;
    return avail[_rng.nextInt(avail.length)];
  }

  // 对齐：保证每个组都有 slot + 颜色；清理已删组；+ 停在空闲栈顶
  void _reconcile(Size area) {
    final fields = widget.config.groups.map((g) => g.field).toList();
    final fieldSet = fields.toSet();
    _groupSlot.removeWhere((f, _) => !fieldSet.contains(f));
    _groupColor.removeWhere((f, _) => !fieldSet.contains(f));
    for (final f in fields) {
      _groupSlot[f] ??= _acquireSlot(area);
      _groupColor[f] ??= _pickColor();
    }
    // 清理空闲栈里已被占用的项
    final used = _groupSlot.values.toSet();
    _freeStack.removeWhere((s) => used.contains(s) || s >= _slots.length);

    if (_holdPlus) {
      // poof 进行中：+ 冻结在原位，待烟雾结束再释放点位重算
      return;
    }
    if (widget.config.groups.length < kMaxGroups) {
      // + 停在空闲栈顶（下一个会被填的位）；栈空则采样一个新点位给 +
      if (_freeStack.isEmpty) {
        _sampleNewSlot(area);
        _freeStack.add(_slots.length - 1);
      }
      _plusSlot = _freeStack.last;
    } else {
      _plusSlot = null;
    }
  }

  // —— 开箱：用户点盒子触发。此刻主线程无转场动画，散布计算放心同步跑 ——
  void _onTapBox() {
    if (_stage != _Stage.boxIdle || _area == null) return;
    setState(() {
      _slots.clear();
      _groupSlot.clear();
      _groupColor.clear();
      _freeStack.clear();
      _reconcile(_area!); // 一次性算好点位+颜色（每次开箱都重算 → 天然每次不同）
      _atCenter = true;
      _stage = _Stage.opening; // 盒子层据此播放 open + burst
    });
  }

  // box_open 的打开段播放完毕（盒子层回调）：盒子停在最后一帧，停顿后再出胶囊
  void _onOpenDone() {
    if (!mounted || _stage != _Stage.opening) return;
    // 停顿 200ms（盒子保持在打开最后一帧），避免开箱太仓促
    _flyTimer?.cancel();
    _flyTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || _stage != _Stage.opening) return;
      setState(() => _stage = _Stage.scattering);
      // 下一帧把胶囊从中心放飞到各自点位（AnimatedPositioned 负责"先快后慢"飞行）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _atCenter = false);
      });
      _flyTimer = Timer(kFlyDuration + const Duration(milliseconds: 80), () {
        if (!mounted) return;
        setState(() => _stage = _Stage.ready);
        ref.read(viewSceneReadyProvider.notifier).set(true); // 通知 shell：可显示搜索
      });
    });
  }

  // —— 数据变更（持久化 + 上抛）——
  String _nextField() {
    final used = widget.config.groups.map((g) => g.field).toSet();
    var i = 1;
    while (used.contains('styles$i')) {
      i++;
    }
    return 'styles$i';
  }

  Future<void> _addGroup() async {
    final ng = [...widget.config.groups, StyleGroup(_nextField(), '', <String>[])];
    await _commit(StylesConfig(ng));
  }

  Future<void> _deleteGroup(String field, {bool releaseSlot = true}) async {
    // 释放该组 slot 压入空闲栈顶（+ 会停在栈顶）；releaseSlot=false 时延后释放（poof 期间）
    if (releaseSlot) {
      final released = _groupSlot[field];
      if (released != null && !_freeStack.contains(released)) {
        _freeStack.add(released);
      }
    }
    final ng = widget.config.groups.where((g) => g.field != field).toList();
    setState(() => _greyField = null);
    await _commit(StylesConfig(ng));
  }

  // 计算胶囊实际渲染宽（与 _GroupCapsule 一致），用于烟雾/＋居中
  double _capsuleWidth(String name) {
    final empty = name.trim().isEmpty;
    if (empty) return 52; // padding 22*2 + 8
    final tp = TextPainter(
      text: TextSpan(
          text: name,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width + 36; // padding 18*2
    return w.clamp(44, kCapsuleMaxWidth).toDouble();
  }

  // 双击已变灰的空组 → 在胶囊正中心播放烟雾；点位调整为"poof 中心"，烟雾结束后 + 飞到该点
  void _destroyGreyed(StyleGroup g) {
    final slot = _groupSlot[g.field];
    if (slot == null || slot >= _slots.length) {
      _deleteGroup(g.field);
      return;
    }
    HapticFeedback.mediumImpact();
    final releasedSlot = slot;
    final oldPos = _slots[slot];
    final capW = _capsuleWidth(g.name);
    // 被删胶囊的实际中心（烟雾就该炸在这里）
    final centerX = oldPos.dx + capW / 2;
    final centerY = oldPos.dy + kCapsuleHeight / 2;
    // 把该 slot 的点位更新为"让 +(宽54) 中心落在该 poof 中心"的左上角，
    // 这样回来的 + 与之后点 + 生成的新胶囊都以这个共享点为锚，不再偏。
    final newSlotPos = Offset(centerX - 54 / 2, oldPos.dy);
    setState(() {
      _holdPlus = true; // 冻结 + 位置（删除引发的 reconcile 不动 +）
      _slots[releasedSlot] = newSlotPos; // 点位随删除调整到共享点
      // 烟雾框 120×120，居中到被删胶囊实际中心
      _poof = _Poof(Offset(centerX - 60, centerY - 60));
      _greyField = null;
    });
    // 数据层删除该组（胶囊消失），但先不释放 slot → + 不动
    _deleteGroup(g.field, releaseSlot: false);
    // 约 70%（~500ms）就释放点位让 + 飞，与烟雾收尾重叠，避免空档"楞一下"
    _plusFlyTimer?.cancel();
    _plusFlyTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _holdPlus = false;
        if (!_freeStack.contains(releasedSlot) &&
            releasedSlot < _slots.length) {
          _freeStack.add(releasedSlot);
        }
        if (_area != null) _reconcile(_area!); // + 开始飞向共享点
      });
    });
    // poof 自然播完后移除（不被硬切断）
    _poofTimer?.cancel();
    _poofTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _poof = null);
    });
  }

  Future<void> _renameGroup(String field, String name) async {
    final ng = widget.config.groups
        .map<StyleGroup>(
            (g) => g.field == field ? StyleGroup(g.field, name, g.styles) : g)
        .toList();
    await _commit(StylesConfig(ng));
  }

  Future<void> _setGroupStyles(String field, List<String> styles) async {
    // 直接 new：保留 name、换 styles（不会抹掉组名）
    final ng = widget.config.groups
        .map<StyleGroup>(
            (g) => g.field == field ? StyleGroup(g.field, g.name, styles) : g)
        .toList();
    await _commit(StylesConfig(ng));
  }

  Future<void> _commit(StylesConfig cfg) async {
    await StylesRepo.save(widget.creds, widget.share, cfg);
    widget.onConfigChanged(cfg); // → ViewPage setState → 本场景 didUpdateWidget → reconcile
  }

  // —— 交互 ——
  String? _shakeField; // 当前要抖动的胶囊
  int _shakeTick = 0; // 每次长按 +1，驱动胶囊重播抖动

  void _longPressCapsule(StyleGroup g) {
    if (g.styles.isEmpty) {
      // 空组：长按变灰、不可交互，双击销毁
      HapticFeedback.mediumImpact();
      setState(() => _greyField = g.field);
    } else {
      // 非空组：震动两下 + 胶囊视觉抖动，保护已登记的组不被误删
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
      setState(() {
        _shakeField = g.field;
        _shakeTick++;
      });
    }
  }

  void _openPanel(StyleGroup g) {
    final colorIdx = _groupColor[g.field] ?? 1;
    showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      barrierDismissible: false, // 改名时点外侧先收键盘，由面板自己处理
      builder: (_) => _GroupPanel(
        creds: widget.creds,
        share: widget.share,
        config: widget.config,
        field: g.field,
        colorIdx: colorIdx,
        initialName: g.name,
        initialStyles: g.styles,
        onRename: (n) => _renameGroup(g.field, n),
        onSetStyles: (s) => _setGroupStyles(g.field, s),
      ),
    ).then((picked) {
      if (picked != null && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PeoplePage(
            creds: widget.creds,
            stylePath: '${widget.share}/$picked',
            styleName: picked,
          ),
        ));
      }
    });
  }

  void _openInbox() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DirBrowserScaffold(
          creds: widget.creds,
          dirPath: widget.share,
          isInbox: true,
          isRoot: true),
    ));
  }

  void _openBlindbox() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlindboxPage(creds: widget.creds, share: widget.share),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.config.groups;
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = Size(constraints.maxWidth, constraints.maxHeight);
        final showBox = _stage == _Stage.boxIdle || _stage == _Stage.opening;
        final showCapsules =
            _stage == _Stage.scattering || _stage == _Stage.ready;
        final isReady = _stage == _Stage.ready;
        final center = _centerTopLeft(_area!);

        return Stack(
          children: [
            // 背景点击：取消"变灰待删"态
            if (isReady)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_greyField != null) setState(() => _greyField = null);
                  },
                ),
              ),

            // 盒子层（待机/打开）
            if (showBox)
              Positioned(
                left: _area!.width / 2 - kBoxSize / 2,
                top: _insetRect(_area!).center.dy - kBoxSize / 2,
                width: kBoxSize,
                height: kBoxSize,
                child: _BoxLayer(stage: _stage, onTap: _onTapBox, onOpenDone: _onOpenDone),
              ),

            // 组胶囊
            if (showCapsules)
              for (final g in groups)
                Builder(builder: (_) {
                  final slot = _groupSlot[g.field];
                  if (slot == null || slot >= _slots.length) {
                    return const SizedBox.shrink();
                  }
                  final pos = _atCenter ? center : _slots[slot];
                  return AnimatedPositioned(
                    key: ValueKey('cap_${g.field}'),
                    duration: kFlyDuration,
                    curve: Curves.easeOutCubic,
                    left: pos.dx,
                    top: pos.dy,
                    child: AnimatedOpacity(
                      duration: kFlyDuration,
                      curve: Curves.easeOut,
                      opacity: _atCenter ? 0.0 : 1.0,
                      child: AnimatedScale(
                        duration: kFlyDuration,
                        curve: Curves.easeOutCubic,
                        scale: _atCenter ? 0.4 : 1.0,
                        child: _GroupCapsule(
                          name: g.name,
                          colorIdx: _groupColor[g.field] ?? 1,
                          greyed: _greyField == g.field,
                          shakeTick: _shakeField == g.field ? _shakeTick : 0,
                          onTap: () => _openPanel(g),
                          onLongPress: () => _longPressCapsule(g),
                          onDoubleTapDestroy: () => _destroyGreyed(g),
                        ),
                      ),
                    ),
                  );
                }),

            // + 胶囊（占一个散布点位；满 20 组时不出现）
            if (showCapsules && _plusSlot != null && _plusSlot! < _slots.length)
              AnimatedPositioned(
                key: const ValueKey('cap_plus'),
                duration: kFlyDuration,
                curve: Curves.easeOutCubic,
                left: _atCenter ? center.dx : _slots[_plusSlot!].dx,
                top: _atCenter ? center.dy : _slots[_plusSlot!].dy,
                child: AnimatedOpacity(
                  duration: kFlyDuration,
                  opacity: _atCenter ? 0.0 : 1.0,
                  child: AnimatedScale(
                    duration: kFlyDuration,
                    curve: Curves.easeOutCubic,
                    scale: _atCenter ? 0.4 : 1.0,
                    child: _AddCapsule(onTap: _addGroup),
                  ),
                ),
              ),

            // 销毁烟雾（已按被删胶囊实际中心算好框左上角）
            if (_poof != null)
              Positioned(
                left: _poof!.boxTopLeft.dx,
                top: _poof!.boxTopLeft.dy,
                width: 120,
                height: 120,
                child: IgnorePointer(
                  child: Lottie.asset(
                    kPoofAsset,
                    repeat: false,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

            // 顶部 inbox / blindbox：仅开箱完成后出现
            if (isReady)
              Positioned(
                left: 12,
                right: 12,
                top: 0,
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _openInbox,
                      icon: const Icon(Symbols.swap_horiz,
                          color: View_C.barBg, size: 22),
                      tooltip: 'Browse files',
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _openBlindbox,
                      icon: const Icon(Symbols.compare_arrows,
                          color: View_C.barBg, size: 22),
                      tooltip: 'Blindbox',
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============ 盒子层：box_open（idle 循环 + open）+ box_burst 叠加 ============
class _BoxLayer extends ConsumerStatefulWidget {
  final _Stage stage;
  final VoidCallback onTap;
  final VoidCallback onOpenDone;
  const _BoxLayer(
      {required this.stage, required this.onTap, required this.onOpenDone});
  @override
  ConsumerState<_BoxLayer> createState() => _BoxLayerState();
}

class _BoxLayerState extends ConsumerState<_BoxLayer>
    with TickerProviderStateMixin {
  late final AnimationController _box = AnimationController(vsync: this);
  late final AnimationController _burst = AnimationController(vsync: this);
  Timer? _idleTimer;
  bool _booted = false;
  bool _opening = false;
  ProviderSubscription<int>? _bumpSub;

  @override
  void initState() {
    super.initState();
    // 只注册一次：每次切进 View（bump）立即定格盒子，延迟到底栏动画结束再循环。
    // 放在 initState 用 listenManual，避免每次 build 重注册造成的时机抖动。
    _bumpSub = ref.listenManual(viewRefreshProvider, (_, __) {
      if (widget.stage == _Stage.boxIdle) _freezeThenIdle();
    });
  }

  @override
  void didUpdateWidget(_BoxLayer old) {
    super.didUpdateWidget(old);
    if (old.stage == _Stage.boxIdle &&
        widget.stage == _Stage.opening &&
        !_opening) {
      _playOpen();
    }
  }

  // 帧安全 #1：切到 View 的那一帧，盒子必须完全静止。
  // 先立刻 stop 并定格首帧，再延迟到底栏动画结束后只循环"待机段" [0, kIdleEnd]。
  void _freezeThenIdle() {
    _idleTimer?.cancel();
    if (_box.duration == null) return;
    _box.stop();
    _box.value = 0; // 定格首帧，切换帧不推进任何动画
    _idleTimer = Timer(kBoxStartDelay, () {
      if (!mounted || widget.stage != _Stage.boxIdle || _box.duration == null) {
        return;
      }
      // 只循环待机段（不触碰打开段）
      _box.repeat(min: 0.0, max: kIdleEnd, period: _box.duration! * kIdleEnd);
    });
  }

  void _playOpen() {
    if (_box.duration == null) return;
    _opening = true;
    _idleTimer?.cancel();
    _box.stop();
    _box.value = kIdleEnd; // 从待机段末尾接到打开段起点
    final openDur = _box.duration! * (1 - kIdleEnd);
    // 打开段 + 弹幕同起，等"两者中较晚结束的那个"播完，再回调出胶囊（弹幕不被截断）
    final openFut =
        _box.animateTo(1.0, duration: openDur, curve: Curves.easeOut);
    // 兜底：弹幕时长若未就绪，给个默认，避免 forward 抛错
    _burst.duration ??= const Duration(milliseconds: 800);
    final burstFut = _burst.forward(from: 0);
    Future.wait([
      openFut.catchError((_) {}),
      burstFut.catchError((_) {}),
    ]).then((_) {
      if (mounted) widget.onOpenDone();
    });
  }

  @override
  void dispose() {
    _bumpSub?.close();
    _idleTimer?.cancel();
    _box.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Lottie.asset(
            kBoxAsset,
            controller: _box,
            fit: BoxFit.contain,
            onLoaded: (comp) {
              _box.duration = comp.duration;
              if (!_booted) {
                _booted = true;
                _freezeThenIdle(); // 首次进入也走"延迟起播"
              }
            },
          ),
          IgnorePointer(
            child: Lottie.asset(
              kBurstAsset,
              controller: _burst,
              fit: BoxFit.contain,
              onLoaded: (comp) => _burst.duration = comp.duration,
            ),
          ),
        ],
      ),
    );
  }
}

// ============ 组胶囊（假标签：显示 name；无 # 前缀）============
class _GroupCapsule extends StatefulWidget {
  final String name;
  final int colorIdx;
  final bool greyed; // 长按变灰待删态：不可点进面板，双击销毁
  final int shakeTick; // 变化即播放一次抖动
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTapDestroy;
  const _GroupCapsule({
    super.key,
    required this.name,
    required this.colorIdx,
    required this.greyed,
    required this.shakeTick,
    required this.onTap,
    required this.onLongPress,
    required this.onDoubleTapDestroy,
  });
  @override
  State<_GroupCapsule> createState() => _GroupCapsuleState();
}

class _GroupCapsuleState extends State<_GroupCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  late final double _phase = (widget.name.hashCode % 100) / 100.0;

  @override
  void didUpdateWidget(_GroupCapsule old) {
    super.didUpdateWidget(old);
    // 变灰态：持续抖动（仿 iOS 编辑）；退出变灰：停止
    if (widget.greyed && !old.greyed) {
      _shake.repeat(period: const Duration(milliseconds: 200));
    } else if (!widget.greyed && old.greyed) {
      _shake.stop();
      _shake.reset();
    }
    // 非灰态的一次性提示抖动（长按保护组时）
    if (!widget.greyed &&
        widget.shakeTick != 0 &&
        widget.shakeTick != old.shakeTick) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Style_C.bg(widget.colorIdx);
    final ink = Style_C.ink(widget.colorIdx);
    final empty = widget.name.trim().isEmpty;
    final grey = widget.greyed;

    Widget capsule = Material(
      color: grey ? const Color(0xFFBFC3C7) : bg, // 变灰
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        // 变灰态：单击不进面板也不删；只有双击销毁
        onTap: grey ? () {} : widget.onTap,
        onDoubleTap: grey ? widget.onDoubleTapDestroy : null,
        onLongPress: grey ? null : widget.onLongPress,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 44,
            maxWidth: kCapsuleMaxWidth,
            minHeight: kCapsuleHeight,
          ),
          padding: EdgeInsets.symmetric(horizontal: empty ? 22 : 18),
          // 不要 alignment:center —— 它会让 Container 撑满 maxWidth。
          // 用 Center 包裹文字实现居中，Container 仍按内容收缩。
          child: Center(
            widthFactor: 1, // 横向贴合内容，不撑开
            child: empty
                ? const SizedBox(width: 8)
                : Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: grey ? Colors.white : ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ),
    );

    // 变灰态降低不透明度，强化"待删除"观感
    if (grey) capsule = Opacity(opacity: 0.7, child: capsule);

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        if (widget.greyed) {
          // 变灰态：稳定旋转抖动（仿 iOS，带相位差）
          final angle = sin((_shake.value + _phase) * pi * 2) * 0.04;
          return Transform.rotate(angle: angle, child: child);
        }
        // 非灰态：一次性阻尼平移（长按保护提示）
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 7 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: capsule,
    );
  }
}

class _AddCapsule extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCapsule({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: View_C.barBg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: const SizedBox(
          width: 54,
          height: kCapsuleHeight,
          child: Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ============ 组面板：组名 + CupertinoPicker + Cancel/Done；点真空白 → 加风格 ============
class _GroupPanel extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  final StylesConfig config;
  final String field;
  final int colorIdx;
  final String initialName;
  final List<String> initialStyles;
  final ValueChanged<String> onRename;
  final ValueChanged<List<String>> onSetStyles;
  const _GroupPanel({
    required this.creds,
    required this.share,
    required this.config,
    required this.field,
    required this.colorIdx,
    required this.initialName,
    required this.initialStyles,
    required this.onRename,
    required this.onSetStyles,
  });
  @override
  State<_GroupPanel> createState() => _GroupPanelState();
}

class _GroupPanelState extends State<_GroupPanel> {
  late List<String> _styles;
  late String _name;
  bool _editingName = false;
  int _sel = 0;
  late final FixedExtentScrollController _wheel;
  late final TextEditingController _nameCtrl;
  late final FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    _styles = [...widget.initialStyles];
    _name = widget.initialName;
    _wheel = FixedExtentScrollController();
    _nameCtrl = TextEditingController(text: _name);
    _nameFocus = FocusNode();
    // 失焦即保存：点任意处让键盘收下，自动完成改名（不必按键盘 ✔）
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingName) _commitName();
    });
  }

  @override
  void dispose() {
    _wheel.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _openEditor() async {
    final entries = await SmbClient.list(widget.creds, widget.share);
    // 被"其他组"登记的文件夹 = 全部登记 − 当前组已选（用最新 _styles，不用旧 config 快照）
    final othersRegistered =
        widget.config.allRegistered.difference(_styles.toSet());
    final candidates = entries
        .where((e) => e.isDir && !_ignoredTop(e.name))
        .map((e) => e.name)
        // 排除被其他组占用的；当前组已选的不放进候选（由 _GroupEditor 的 current 单独显示）
        .where((n) => !othersRegistered.contains(n))
        .where((n) => !_styles.contains(n))
        .toList();
    if (!mounted) return;
    final result = await showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => _GroupEditor(
          current: _styles,
          candidates: candidates,
          colorIdx: widget.colorIdx),
    );
    if (result == null) return;
    setState(() {
      _styles = result;
      if (_sel >= _styles.length) _sel = 0;
    });
    widget.onSetStyles(result);
  }

  void _commitName() {
    final n = _nameCtrl.text.trim();
    setState(() {
      _name = n;
      _editingName = false;
    });
    widget.onRename(n);
  }

  @override
  Widget build(BuildContext context) {
    final bg = Style_C.bg(widget.colorIdx);
    final ink = Style_C.ink(widget.colorIdx);
    final canDone = _styles.isNotEmpty;

    return Stack(
      children: [
        // 点面板外侧：改名时先收键盘（不关闭）；否则关闭面板
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_editingName) {
                FocusScope.of(context).unfocus();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            // 点面板任意处：仅收起键盘/失焦（失焦会自动保存组名）。
            // 进入"选文件夹"改由滚轮区单/双击触发，不再用整面板空白。
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 组名：点击就地改名；无名显示小字提示。整块吸收点击，
                  // 周围一圈不会冒泡到外层"点空白加风格"
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _editingName = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                alignment: Alignment.center,
                child: _editingName
                  ? TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      cursorColor: ink,
                      style: TextStyle(
                          color: ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                          border: InputBorder.none, isCollapsed: true),
                      onSubmitted: (_) => _commitName(),
                    )
                  : Text(
                      _name.trim().isEmpty ? 'Tap to name' : _name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _name.trim().isEmpty
                            ? ink.withOpacity(0.45)
                            : ink,
                        fontSize: _name.trim().isEmpty ? 15 : 20,
                        fontWeight: _name.trim().isEmpty
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 8),
            // 滚轮区：唯一能进入"选文件夹"的区域。
            // 空组 → 单击进入；已有风格 → 双击进入（单击只用于滚轮本身，防误触）。
            SizedBox(
              height: 180,
              child: _styles.isEmpty
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 正在改名时，先收键盘而不是直接进文件夹（防误触）
                        if (_editingName) {
                          FocusScope.of(context).unfocus();
                        } else {
                          _openEditor();
                        }
                      },
                      child: Center(
                        child: Text('Tap here to add styles',
                            style: TextStyle(
                                color: ink.withOpacity(0.5), fontSize: 13)),
                      ),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _openEditor, // 已有风格：双击进入
                      onTap: () {}, // 单击吸收，不触发
                      child: CupertinoPicker(
                        scrollController: _wheel,
                        itemExtent: 40,
                        backgroundColor: Colors.transparent,
                        // 窄高亮条：按当前选中项文字宽度精确贴合
                        selectionOverlay: Builder(builder: (_) {
                          final label =
                              '#${_sel < _styles.length ? _styles[_sel] : ''}';
                          final tp = TextPainter(
                            text: TextSpan(
                                text: label,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                            textDirection: TextDirection.ltr,
                          )..layout();
                          return Center(
                            child: Container(
                              width: tp.width + 28, // 文字宽 + 左右内边距
                              height: 38,
                              decoration: BoxDecoration(
                                color: ink.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }),
                        onSelectedItemChanged: (i) =>
                            setState(() => _sel = i),
                        children: [
                          for (final s in _styles)
                            Center(
                              child: Text('#$s',
                                  style: TextStyle(
                                      color: ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque, // 整行吸收点击，不冒泡到外层选文件夹
              onTap: () {},
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: ink.withOpacity(0.6),
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canDone
                          ? () => Navigator.pop(context, _styles[_sel])
                          : null,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text('Done',
                            style: TextStyle(
                                color: canDone ? ink : ink.withOpacity(0.3),
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
        ),
      ),
        ), // Center
      ], // Stack children
    ); // Stack
  }
}

// ============ 文件夹登记网格（从磁盘真实文件夹挑选加入组）============
class _GroupEditor extends StatefulWidget {
  final List<String> current;
  final List<String> candidates;
  final int colorIdx; // 跟随胶囊配色
  const _GroupEditor(
      {required this.current,
      required this.candidates,
      required this.colorIdx});
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late Set<String> _selected; // 已勾选
  late List<String> _all; // 全部文件夹的显示顺序（已选在前 + 候选在后，可拖动重排）
  bool _sorting = false; // 排序态（长按进入）

  @override
  void initState() {
    super.initState();
    _selected = widget.current.toSet();
    // 初始顺序：已选(按 current 顺序) + 候选
    _all = [...widget.current, ...widget.candidates];
  }

  // 返回结果：按 _all 的全局顺序，取出其中被勾选的
  List<String> _result() => _all.where(_selected.contains).toList();

  void _toggle(String name) {
    setState(() {
      _selected.contains(name)
          ? _selected.remove(name)
          : _selected.add(name);
    });
  }

  void _enterSorting() {
    HapticFeedback.mediumImpact();
    setState(() => _sorting = true);
  }

  void _exitSorting() => setState(() => _sorting = false);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bg = Style_C.bg(widget.colorIdx);
    final ink = Style_C.ink(widget.colorIdx);

    return PopScope(
      // 排序态：系统返回退出排序态而非关面板；非排序态正常允许关闭
      canPop: !_sorting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _sorting) _exitSorting();
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_sorting ? 'Drag to reorder' : 'Edit styles',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ink)),
                      const Spacer(),
                      // 排序态：右上角小 Done 退出排序
                      if (_sorting)
                        GestureDetector(
                          onTap: _exitSorting,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Text('Done',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ink)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: size.height * 0.42,
                    child: _all.isEmpty
                        ? Center(
                            child: Text('No folders available',
                                style:
                                    TextStyle(color: ink.withOpacity(0.6))))
                        : (_sorting
                            ? ReorderableGridView.count(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1.0,
                                // 拖动时跟手的替身：用透明 Material 包卡片，
                                // 去掉默认那层白底方块
                                // 拖动跟手替身：不透明底 + 圆角 + 阴影，盖住下层、有浮起感
                                dragWidgetBuilder: (index, child) => Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: bg, // 不透明面板底，盖住下面
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(0.18),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                ),
                                // 被拖走原位的占位：透明，消除白块
                                placeholderBuilder: (dragIndex, dropIndex,
                                        dragWidget) =>
                                    const SizedBox.shrink(),
                                onReorder: (oldI, newI) {
                                  setState(() {
                                    final item = _all.removeAt(oldI);
                                    _all.insert(newI, item);
                                  });
                                },
                                children: [
                                  for (final name in _all)
                                    _ShakingFolder(
                                      key: ValueKey(name),
                                      name: name,
                                      selected: _selected.contains(name),
                                      ink: ink,
                                    ),
                                ],
                              )
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.0,
                                ),
                                itemCount: _all.length,
                                itemBuilder: (_, i) {
                                  final name = _all[i];
                                  return _FolderPick(
                                    name: name,
                                    selected: _selected.contains(name),
                                    ink: ink,
                                    onTap: () => _toggle(name),
                                    onLongPress: _enterSorting,
                                  );
                                },
                              )),
                  ),
                  const SizedBox(height: 16),
                  // 排序态隐藏底部 Done（改用右上角小 Done）
                  if (!_sorting)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, _result()),
                        style: TextButton.styleFrom(
                          backgroundColor: ink,
                          foregroundColor: bg,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Done',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderPick extends StatelessWidget {
  final String name;
  final bool selected;
  final Color ink;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _FolderPick(
      {required this.name,
      required this.selected,
      required this.ink,
      required this.onTap,
      this.onLongPress});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _folderCard(name: name, selected: selected, ink: ink),
    );
  }
}

// 文件夹卡片视觉（_FolderPick 与排序态抖动卡片共用）
Widget _folderCard(
    {required String name, required bool selected, required Color ink}) {
  return Stack(
    children: [
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? ink : ink.withOpacity(0.2),
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_outlined, color: ink, size: 34),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ink, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
      if (selected)
        Positioned(
          top: 6,
          left: 6,
          child: Icon(Icons.check_circle, color: ink, size: 18),
        ),
    ],
  );
}

// 排序态：抖动的文件夹卡片（仿 iOS 编辑态）
class _ShakingFolder extends StatefulWidget {
  final String name;
  final bool selected;
  final Color ink;
  const _ShakingFolder(
      {super.key,
      required this.name,
      required this.selected,
      required this.ink});
  @override
  State<_ShakingFolder> createState() => _ShakingFolderState();
}

class _ShakingFolderState extends State<_ShakingFolder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180))
    ..repeat(reverse: true);
  // 给每个卡片一点相位差，抖得不整齐更自然
  late final double _phase = (widget.name.hashCode % 100) / 100.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final angle = (sin((_c.value + _phase) * pi * 2)) * 0.03; // ±0.03 rad
        return Transform.rotate(angle: angle, child: child);
      },
      child: _folderCard(
          name: widget.name, selected: widget.selected, ink: widget.ink),
    );
  }
}

// ============ 普通模式：文件管理器（原样保留，仅换 View_C 配色）============
class _DirBrowserScaffold extends StatelessWidget {
  final SmbCreds creds;
  final String dirPath;
  final bool isInbox;
  final bool isRoot;
  const _DirBrowserScaffold({
    required this.creds,
    required this.dirPath,
    required this.isInbox,
    this.isRoot = false,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: View_C.bg,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: _DirBrowser(
            creds: creds, dirPath: dirPath, isInbox: isInbox, isRoot: isRoot),
      ),
    );
  }
}

class _DirBrowser extends ConsumerStatefulWidget {
  final SmbCreds creds;
  final String dirPath;
  final bool isInbox;
  final bool isRoot;
  const _DirBrowser({
    required this.creds,
    required this.dirPath,
    required this.isInbox,
    this.isRoot = false,
  });
  @override
  ConsumerState<_DirBrowser> createState() => _DirBrowserState();
}

class _DirBrowserState extends ConsumerState<_DirBrowser> {
  List<SmbEntry> _entries = [];
  bool _loading = true;
  SmbEntry? _selecting;
  // 受保护项（. 或 _ 开头）长按时抖动提示，不进入重命名/移动
  String? _shakeName;
  int _shakeTick = 0;

  // . 或 _ 开头：可进入查看，但不可改名/移动（防误操作约定项）。
  // 注：系统隐藏文件由 native(MainActivity.kt) 按 SMB 属性自动过滤，这里不再手动列名单。
  bool _isProtected(String name) =>
      name.startsWith('.') || name.startsWith('_');

  String get _dir => widget.dirPath;
  String get _title {
    final i = _dir.lastIndexOf('/');
    return i >= 0 ? _dir.substring(i + 1) : _dir;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SmbClient.list(widget.creds, _dir);
    // 系统隐藏文件已由 native 按 SMB 属性过滤；这里只排序
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  void _enter(String name) {
    if (_selecting != null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DirBrowserScaffold(
        creds: widget.creds,
        dirPath: '$_dir/$name',
        isInbox: widget.isInbox,
      ),
    ));
  }

  void _openFile(String name) {
    if (isImageFile(name)) {
      final imgs = _entries
          .where((e) => !e.isDir && isImageFile(e.name))
          .map((e) => e.name)
          .toList();
      final idx = imgs.indexOf(name);
      openImageViewer(context, widget.creds, _dir, imgs, idx < 0 ? 0 : idx);
    } else if (isTextFile(name)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextPage(
            creds: widget.creds, filePath: '$_dir/$name', fileName: name),
      ));
    } else if (_isVideo(name)) {
      SmbClient.openExternal(widget.creds, '$_dir/$name');
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text("Can't open this file type in nook"),
          duration: Duration(seconds: 2),
        ));
    }
  }

  void _longPress(SmbEntry e) {
    HapticFeedback.mediumImpact();
    if (_isProtected(e.name)) {
      // 受保护：抖动两下提示，不进入重命名/移动
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
      setState(() {
        _shakeName = e.name;
        _shakeTick++;
      });
      return;
    }
    setState(() => _selecting = e);
  }

  void _cancelSelect() => setState(() => _selecting = null);

  Future<void> _doRename(SmbEntry e) async {
    final ctrl = TextEditingController(text: e.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: View_C.surface,
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == e.name) {
      _cancelSelect();
      return;
    }
    try {
      await SmbClient.move(widget.creds, '$_dir/${e.name}', '$_dir/$newName');
      _cancelSelect();
      _load();
    } catch (err) {
      _showError('$err');
      _cancelSelect();
    }
  }

  void _startMove(SmbEntry e) {
    ref.read(pendingMoveProvider.notifier).lock(PendingMove(
          fromPath: '$_dir/${e.name}',
          name: e.name,
          isDir: e.isDir,
        ));
    setState(() => _selecting = null);
  }

  Future<void> _paste(PendingMove pm) async {
    final target = '$_dir/${pm.name}';
    if (target == pm.fromPath) {
      ref.read(pendingMoveProvider.notifier).clear();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: View_C.surface,
        content: Text('Move "${pm.name}" here?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Move')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SmbClient.move(widget.creds, pm.fromPath, target);
      ref.read(pendingMoveProvider.notifier).clear();
      _load();
    } catch (err) {
      _showError('$err');
    }
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: View_C.surface,
        title: const Text('Failed'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _exitInbox() {
    ref.read(pendingMoveProvider.notifier).clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingMoveProvider);
    return PopScope(
      canPop: !widget.isRoot,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
                child: Row(
                  children: [
                    if (_selecting != null)
                      IconButton(
                        onPressed: _cancelSelect,
                        icon: const Icon(Icons.close,
                            size: 20, color: View_C.ink),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    else
                      IconButton(
                        onPressed: widget.isRoot
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.arrow_back_ios_new,
                            size: 18,
                            color: widget.isRoot
                                ? View_C.inkSoft.withOpacity(0.3)
                                : View_C.ink),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_title,
                          style:
                              const TextStyle(color: View_C.ink, fontSize: 15),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (widget.isInbox && _selecting == null)
                      TextButton(
                        onPressed: _exitInbox,
                        child: const Text('Exit',
                            style:
                                TextStyle(color: View_C.accent, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: View_C.accent))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: View_C.line, height: 1),
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          final isText = !e.isDir && isTextFile(e.name);
                          final isVid = !e.isDir && _isVideo(e.name);
                          final isImg = !e.isDir && isImageFile(e.name);
                          final isSel = identical(e, _selecting);
                          return _ShakeRow(
                            tick: _shakeName == e.name ? _shakeTick : 0,
                            child: Container(
                            decoration: isSel
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: View_C.accent, width: 2),
                                  )
                                : null,
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              leading: Icon(
                                e.isDir
                                    ? Icons.folder_outlined
                                    : (isVid
                                        ? Icons.play_circle_outline
                                        : (isImg
                                            ? Icons.image_outlined
                                            : (isText
                                                ? Icons.description_outlined
                                                : Icons
                                                    .insert_drive_file_outlined))),
                                color: e.isDir ? View_C.accent : View_C.inkSoft,
                              ),
                              title: Text(e.name,
                                  style: const TextStyle(
                                      color: View_C.ink, fontSize: 14)),
                              onTap: _selecting != null
                                  ? null
                                  : (e.isDir
                                      ? () => _enter(e.name)
                                      : () => _openFile(e.name)),
                              onLongPress: () => _longPress(e),
                            ),
                          ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (_selecting != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 92,
              child: _BottomActionBar(children: [
                _ActionChip(
                    label: 'Rename',
                    icon: Icons.drive_file_rename_outline,
                    onTap: () => _doRename(_selecting!)),
                _ActionChip(
                    label: 'Move',
                    icon: Icons.drive_file_move_outline,
                    onTap: () => _startMove(_selecting!)),
              ]),
            )
          else if (pending != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 92,
              child: _BottomActionBar(children: [
                _ActionChip(
                    label: 'Cancel',
                    icon: Icons.close,
                    onTap: () =>
                        ref.read(pendingMoveProvider.notifier).clear()),
                _ActionChip(
                    label: 'Paste',
                    icon: Icons.content_paste,
                    highlight: true,
                    enabled: _dir !=
                        pending.fromPath
                            .substring(0, pending.fromPath.lastIndexOf('/')),
                    onTap: () => _paste(pending)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final List<Widget> children;
  const _BottomActionBar({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: View_C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: View_C.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  final bool enabled;
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.highlight = false,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? View_C.inkSoft.withOpacity(0.35)
        : (highlight ? View_C.accent : View_C.ink);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ 盲盒：平铺所有视频（原样保留，仅换 View_C 配色）============
class BlindboxPage extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  const BlindboxPage({super.key, required this.creds, required this.share});
  @override
  State<BlindboxPage> createState() => _BlindboxPageState();
}

// 盲盒单个胶囊的随机外观（缓存用）
class _BlindItem {
  final String path;
  final int colorIdx; // 1..20
  final double width; // 随机宽
  _BlindItem(this.path, this.colorIdx, this.width);
}

// 按 share 缓存盲盒布局：第一次进随机一次，同 share 复用，换 share 由 Link 清掉
class _BlindboxCache {
  static final Map<String, List<_BlindItem>> _byShare = {};
  static List<_BlindItem>? get(String share) => _byShare[share];
  static void put(String share, List<_BlindItem> items) =>
      _byShare[share] = items;
  static void clear(String share) => _byShare.remove(share);
  static void clearAll() => _byShare.clear();
}

class _BlindboxPageState extends State<BlindboxPage> {
  List<_BlindItem> _items = [];
  bool _loading = true;
  final _rng = Random();

  String get _root => '${widget.share}/_blindbox';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 有缓存直接用（同 share 不重新随机）
    final cached = _BlindboxCache.get(widget.share);
    if (cached != null) {
      setState(() {
        _items = cached;
        _loading = false;
      });
      return;
    }
    // 首次：扫盘 + 随机生成布局 + 缓存
    final found = <String>[];
    await _walk(_root, found);
    if (!mounted) return;
    final items = found
        .map((p) => _BlindItem(
              p,
              _rng.nextInt(20) + 1, // 随机色
              90.0 + _rng.nextInt(110), // 随机宽 90~200
            ))
        .toList();
    _BlindboxCache.put(widget.share, items);
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _walk(String path, List<String> out) async {
    List<SmbEntry> entries;
    try {
      entries = await SmbClient.list(widget.creds, path);
    } catch (_) {
      return;
    }
    for (final e in entries) {
      if (e.isDir) {
        await _walk('$path/${e.name}', out);
      } else if (_isVideo(e.name)) {
        out.add('$path/${e.name}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: View_C.bg,
      appBar: AppBar(
        backgroundColor: View_C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new,
              color: View_C.ink, size: 20),
        ),
        title: const Text('Blindbox',
            style: TextStyle(
                color: View_C.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: View_C.accent))
          : _items.isEmpty
              ? const Center(
                  child: Text('Empty', style: TextStyle(color: View_C.inkSoft)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  child: Wrap(
                    spacing: 12, // 横向间距
                    runSpacing: 16, // 行间距
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final it in _items)
                        Padding(
                          // 随机垂直微偏移，制造错落"散"感（不重叠）
                          padding: EdgeInsets.only(
                              top: (it.path.hashCode % 3) * 6.0),
                          child: _BlindCapsule(
                            colorIdx: it.colorIdx,
                            width: it.width,
                            onTap: () =>
                                SmbClient.openExternal(widget.creds, it.path),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// 盲盒胶囊：纯色、无图标无文字、随机色随机宽
class _BlindCapsule extends StatelessWidget {
  final int colorIdx;
  final double width;
  final VoidCallback onTap;
  const _BlindCapsule(
      {required this.colorIdx, required this.width, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bg = Style_C.bg(colorIdx);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(width: width, height: 44),
      ),
    );
  }
}

// 受保护项（. / _ 开头）长按时的一次性左右抖动提示
class _ShakeRow extends StatefulWidget {
  final int tick; // 变化即播放一次抖动（0 表示不抖）
  final Widget child;
  const _ShakeRow({required this.tick, required this.child});
  @override
  State<_ShakeRow> createState() => _ShakeRowState();
}

class _ShakeRowState extends State<_ShakeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(_ShakeRow old) {
    super.didUpdateWidget(old);
    if (widget.tick != 0 && widget.tick != old.tick) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 7 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}