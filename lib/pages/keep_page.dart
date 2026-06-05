import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lottie/lottie.dart';
import 'package:lpinyin/lpinyin.dart';
import '../theme.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../models/styles.dart';
import '../models/person.dart';
import '../models/keep_index.dart';
import '../models/cover_index.dart';
import '../widgets.dart';
import 'person_page.dart';

/// Keep 浏览模式
enum KeepMode { random, date, person }

class KeepPage extends ConsumerStatefulWidget {
  const KeepPage({super.key});
  @override
  ConsumerState<KeepPage> createState() => _KeepPageState();
}

class _KeepPageState extends ConsumerState<KeepPage> {
  String? _loadedShare;
  bool _loading = false;
  bool _rebuilding = false;
  List<IndexItem>? _items; // null=无索引/未加载
  bool _notSpecific = false; // 当前 share 非特定库

  KeepMode _mode = KeepMode.random;
  List<IndexItem> _shuffled = []; // 随机模式的稳定顺序（进入/刷新时定一次）
  Map<String, double> _coverAr = {}; // 封面路径→宽高比（cover_index，用于瀑布流不跳）
  String? _selectedKey; // 当前选中作品（单选）：personPath + '\u0000' + fileName

  // —— 人物模式（字母盲盒）—— 状态绑定 share，换 share 才重置
  bool _heartBurst = false; // 心是否已爆开（爆后显示一地字母）
  List<String> _letters = []; // 有哪些首字母（A-Z/0/#），去重排序
  List<Offset> _letterSlots = []; // 每个字母的散布点位（top-left）

  @override
  void initState() {
    super.initState();
    // keep 页被 StatefulNavigationShell 永久保活，换 share 时它在后台 build 不跑。
    // 用 listener 主动感知 share 变化 → 重置人物模式（心回到按钮态）。
    ref.listenManual(selectedShareProvider, (prev, next) {
      if (prev != next && mounted) {
        setState(() {
          _heartBurst = false;
          _letters = [];
          _letterSlots = [];
          _loadedShare = null; // 强制下次 build 重新 _init（重算字母/索引）
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final share = ref.watch(selectedShareProvider);
    final conn = ref.watch(connectionProvider);

    if (share == null || conn.creds == null) {
      return const Center(
        child: Text('Pick a Share in Link',
            style: TextStyle(color: Keep_C.inkSoft, fontSize: 16)),
      );
    }

    if (_loadedShare != share && !_loading) {
      _loadedShare = share;
      // 同步重置人物模式（心按钮态），不等 async _init
      _heartBurst = false;
      _letters = [];
      _letterSlots = [];
      _init(conn.creds!, share);
    }

    return Container(
      color: Keep_C.bg,
      child: Stack(
        children: [
          if (_loading || _rebuilding)
            const Center(child: CircularProgressIndicator(color: Keep_C.barBg))
          else if (_notSpecific)
            const Center(
              child: Text('Pick Another Share in Link',
                  style: TextStyle(color: Keep_C.inkSoft)),
            )
          else
            _buildBody(conn.creds!),
          // 右上角：重置索引
          if (!_notSpecific)
            Positioned(
              top: 4,
              right: 16,
              child: _RefreshButton(
                spinning: _rebuilding,
                onTap: () => _rebuild(conn.creds!, share),
              ),
            ),
          // 左上角（汉堡下方）：模式切换
          if (!_notSpecific && !_loading && !_rebuilding)
            Positioned(
              top: 4,
              left: 16,
              child: _ModeButton(
                mode: _mode,
                onTap: _cycleMode,
              ),
            ),
        ],
      ),
    );
  }

  void _cycleMode() {
    setState(() {
      _mode = switch (_mode) {
        KeepMode.random => KeepMode.date,
        KeepMode.date => KeepMode.person,
        KeepMode.person => KeepMode.random,
      };
    });
  }

  Future<void> _init(SmbCreds c, String share) async {
    setState(() {
      _loading = true;
      // 换 share：重置人物模式（心回到未点亮）
      _heartBurst = false;
      _letters = [];
      _letterSlots = [];
    });
    final config = await StylesRepo.load(c, share);
    if (config == null) {
      if (!mounted) return;
      setState(() {
        _notSpecific = true;
        _loading = false;
      });
      return;
    }
    final existing = await IndexRepo.read(share);
    final coverAr = await CoverIndexRepo.read(share);
    if (existing != null) {
      if (!mounted) return;
      setState(() {
        _items = existing;
        _shuffled = [...existing]..shuffle(Random());
        _coverAr = coverAr;
        _letters = _collectLetters(existing);
        _loading = false;
        _notSpecific = false;
      });
    } else {
      setState(() {
        _coverAr = coverAr;
        _loading = false;
      });
      await _rebuild(c, share);
    }
  }

  Future<void> _rebuild(SmbCreds c, String share) async {
    final config = await StylesRepo.load(c, share);
    if (config == null) return;
    setState(() => _rebuilding = true);
    CoverCache.clearAll(); // 重建：清封面缓存，换过的封面重新读
    final items = await IndexRepo.rebuild(c, share, config);
    final coverAr = await CoverIndexRepo.read(share); // 读最新封面比例
    if (!mounted) return;
    setState(() {
      _items = items;
      _shuffled = [...items]..shuffle(Random());
      _coverAr = coverAr;
      _letters = _collectLetters(items);
      _rebuilding = false;
      _notSpecific = false;
    });
  }

  // 收集所有收藏人物的首字母（英文首字母 / 中文拼音首字母 / 数字→0 / 其它→#），去重排序
  List<String> _collectLetters(List<IndexItem> items) {
    final set = <String>{};
    for (final it in items) {
      set.add(_letterOf(it.personName));
    }
    final list = set.toList()..sort(_letterCompare);
    return list;
  }

  String _letterOf(String name) {
    final n = name.trim();
    if (n.isEmpty) return '#';
    final first = n[0];
    // 英文字母
    final code = first.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) return first.toUpperCase();
    // 数字
    if (RegExp(r'[0-9]').hasMatch(first)) return '0';
    // 中文等 → 拼音首字母
    try {
      final py = PinyinHelper.getFirstWordPinyin(n);
      if (py.isNotEmpty) {
        final c0 = py[0].toUpperCase();
        if (c0.codeUnitAt(0) >= 65 && c0.codeUnitAt(0) <= 90) return c0;
      }
    } catch (_) {}
    return '#';
  }

  // 排序：A-Z 在前，0 和 # 殿后
  int _letterCompare(String a, String b) {
    int rank(String s) => s == '#' ? 2 : (s == '0' ? 1 : 0);
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra - rb;
    return a.compareTo(b);
  }

  Widget _buildBody(SmbCreds creds) {
    final items = _items ?? [];
    if (items.isEmpty) {
      return const Center(
        child: Text('Nothing Kept Yet',
            style: TextStyle(color: Keep_C.inkSoft)),
      );
    }
    if (_mode == KeepMode.person) {
      // 人物态：字母盲盒
      if (_letters.isEmpty) {
        return const Center(
          child: Text('Nothing Kept Yet',
              style: TextStyle(color: Keep_C.inkSoft, fontSize: 15)),
        );
      }
      return _BlindboxView(
        key: ValueKey('blindbox_$_loadedShare'),
        letters: _letters,
        burst: _heartBurst,
        slots: _letterSlots,
        onBurstComplete: (slots) {
          setState(() {
            _letterSlots = slots;
            _heartBurst = true;
          });
        },
        onPickLetter: (letter) => _openLetter(creds, letter),
      );
    }
    // 随机 / 日期：作品封面瀑布流
    final list = _mode == KeepMode.random
        ? _shuffled
        : (List<IndexItem>.from(items)
          ..sort((a, b) => b.lovedAt.compareTo(a.lovedAt))); // 最近收藏在前

    return MasonryGridView.count(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 100),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      itemCount: list.length,
      itemBuilder: (_, i) {
        final it = list[i];
        final key = '${it.personPath}\u0000${it.fileName}';
        return _WorkCoverTile(
          creds: creds,
          item: it,
          coverAr: _coverAr,
          selected: _selectedKey == key,
          onSelect: () => _selectWork(key),
          onOpen: () => _openWork(creds, it),
        );
      },
    );
  }

  // 单击：单选切换。点未选中的→选中；再点已选中的→取消高亮
  void _selectWork(String key) {
    setState(() => _selectedKey = _selectedKey == key ? null : key);
  }

  void _openWork(SmbCreds c, IndexItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(
        creds: c,
        person: PersonNode(name: it.personName, path: it.personPath),
        spec: PersonColorSpec.person(it.personName),
        initialWork: it.fileName,
      ),
    ));
  }

  // 点字母：列出该字母下的人（去重），弹浮层选人 → 进人物页
  Future<void> _openLetter(SmbCreds c, String letter) async {
    final items = _items ?? [];
    // 该字母下的人物（按 personPath 去重，保留首次出现）
    final seen = <String>{};
    final people = <IndexItem>[];
    for (final it in items) {
      if (_letterOf(it.personName) != letter) continue;
      if (seen.add(it.personPath)) people.add(it);
    }
    if (people.isEmpty) return;
    final picked = await showDialog<IndexItem>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (dctx) => _LetterPeoplePicker(
        creds: c,
        letter: letter,
        people: people,
        coverAr: _coverAr,
        onPick: (it) => Navigator.of(dctx).pop(it), // 关浮层并返回所选
      ),
    );
    if (picked == null || !mounted) return;
    // 浮层已关闭，再用 keep 的 Navigator 进人物页（只看收藏）
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(
        creds: c,
        person: PersonNode(name: picked.personName, path: picked.personPath),
        spec: PersonColorSpec.person(picked.personName),
        keepLovedOnly: true, // 从 keep 进入：只显示 pin/pre（实时读 _person.json）
      ),
    ));
  }
}

/// 作品封面瀑布流单元：封面真实比例 + 按 love 的渐变描边框 + 选中态 Lottie
class _WorkCoverTile extends StatefulWidget {
  final SmbCreds creds;
  final IndexItem item;
  final Map<String, double> coverAr; // 封面路径→比例字典（按候选链解析）
  final bool selected;
  final VoidCallback onSelect; // 单击：选中
  final VoidCallback onOpen; // 双击：进入作品页
  const _WorkCoverTile({
    required this.creds,
    required this.item,
    required this.coverAr,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  @override
  State<_WorkCoverTile> createState() => _WorkCoverTileState();
}

class _WorkCoverTileState extends State<_WorkCoverTile>
    with TickerProviderStateMixin {
  static const _shineAsset = 'assets/fx_shine.json';
  static const _sparkleAsset = 'assets/fx_sparkle.json';
  static const _gap = Duration(milliseconds: 800); // 每轮之间的间隔
  static const _borderFade = Duration(milliseconds: 260);

  late final AnimationController _shine =
      AnimationController(vsync: this);
  late final AnimationController _sparkle =
      AnimationController(vsync: this);
  // 星粒：先快后慢（decelerate）的非匀速曲线，喂给 Lottie
  late final CurvedAnimation _sparkleCurved =
      CurvedAnimation(parent: _sparkle, curve: Curves.decelerate);
  // 光泽：先快后慢的非匀速曲线（不拉长时长）
  late final CurvedAnimation _shineCurved =
      CurvedAnimation(parent: _shine, curve: Curves.decelerate);

  bool _fxOn = false; // 边框淡入完成后才置 true，开始播动画
  int _phase = 0; // 0=光泽 1=星粒
  Timer? _gapTimer;

  bool get _isPinnacle => widget.item.love == 'pinnacle';

  @override
  void initState() {
    super.initState();
    // 预加载两个 Lottie 的时长，确保 forward() 前 duration 已就绪（否则崩）
    AssetLottie(_shineAsset).load().then((c) {
      if (mounted) _shine.duration = c.duration * 1.5; // 光泽慢 1.5 倍
    });
    AssetLottie(_sparkleAsset).load().then((c) {
      if (mounted) _sparkle.duration = c.duration; // 星粒原时长（仅曲线，不拉长）
    });
    _shine.addStatusListener(_onShineDone);
    _sparkle.addStatusListener(_onSparkleDone);
    if (widget.selected) _scheduleStart();
  }

  @override
  void didUpdateWidget(_WorkCoverTile old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _scheduleStart();
    } else if (!widget.selected && old.selected) {
      _stopFx();
    }
  }

  // 边框淡入完成后再启动动画序列（不打架）
  void _scheduleStart() {
    _gapTimer?.cancel();
    _gapTimer = Timer(_borderFade, () {
      if (!mounted || !widget.selected) return;
      setState(() => _fxOn = true);
      _playShine();
    });
  }

  void _stopFx() {
    _gapTimer?.cancel();
    _shine.stop();
    _sparkle.stop();
    if (mounted) {
      setState(() {
        _fxOn = false;
        _phase = 0;
      });
    }
  }

  void _playShine() {
    if (!mounted || !widget.selected) return;
    setState(() => _phase = 0);
    _shine.duration ??= const Duration(milliseconds: 1800); // 兜底(1200*1.5)
    _shine.forward(from: 0);
  }

  void _onShineDone(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted || !widget.selected) return;
    if (_isPinnacle) {
      // pinnacle：光泽完 → 星粒
      setState(() => _phase = 1);
      _sparkle.duration ??= const Duration(milliseconds: 1500); // 兜底
      _sparkle.forward(from: 0);
    } else {
      // preferred：光泽完 → 间隔 → 再光泽
      _gapTimer?.cancel();
      _gapTimer = Timer(_gap, _playShine);
    }
  }

  void _onSparkleDone(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted || !widget.selected) return;
    // 星粒完 → 间隔 → 回到光泽（完整循环）
    _gapTimer?.cancel();
    _gapTimer = Timer(_gap, _playShine);
  }

  @override
  void dispose() {
    _gapTimer?.cancel();
    _sparkleCurved.dispose();
    _shineCurved.dispose();
    _shine.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  List<String> get _candidates =>
      workCoverCandidates(widget.item.personPath, widget.item.fileName);

  // 按候选链解析已知比例：作品自有封面优先，其次人物封面（与 CoverImage 实际显示一致）
  double? get _resolvedAr {
    for (final cand in _candidates) {
      final v = widget.coverAr[cand];
      if (v != null) return v;
    }
    return null;
  }

  List<Color> get _frameColors => _isPinnacle
      ? const [
          Heart_C.flameOuter,
          Heart_C.flameMid,
          Heart_C.flameInner,
          Heart_C.stroke,
        ]
      : const [
          Heart_C.pinkEnd,
          Heart_C.pinkStart,
          Heart_C.stroke,
        ];

  List<double> get _frameStops =>
      _isPinnacle ? const [0.0, 0.22, 0.42, 1.0] : const [0.0, 0.4, 1.0];

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;
    final cardRadius = BorderRadius.circular(radius);
    // 封面是否偏竖（用已知比例；未知则按 fallback 0.6 当作竖）
    final ar = _resolvedAr ?? 0.6;
    final isTall = ar < 0.8; // 宽高比 <0.8 视为细长 → 星粒上下对角

    return GestureDetector(
      onTap: widget.onSelect, // 单击：选中
      onDoubleTap: widget.onOpen, // 双击：直接进入（任意状态）
      child: Stack(
        children: [
          // 裸封面（默认无边框），圆角裁切
          ClipRRect(
            borderRadius: cardRadius,
            child: Stack(
              children: [
                CoverImage(
                  creds: widget.creds,
                  candidates: _candidates,
                  fallbackName: _stripExt(widget.item.fileName),
                  fallbackColor: Keep_C.surface,
                  fallbackInk: Keep_C.ink,
                  aspectRatioFallback: 0.8,
                  knownAspectRatio: _resolvedAr,
                  fit: BoxFit.cover,
                ),
                // 特效层：RepaintBoundary 隔离重绘，不冒泡到瀑布流（防跳动/卡顿）
                if (_fxOn && _phase == 0)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: Lottie.asset(
                          _shineAsset,
                          controller: _shineCurved,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                if (_fxOn && _phase == 1 && _isPinnacle)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: isTall ? _sparkleMirrored() : _sparkleSingle(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 选中渐变描边（默认无；选中淡入；贴合封面圆角）
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: _borderFade,
                opacity: widget.selected ? 1.0 : 0.0,
                child: _GradientBorder(
                  radius: radius,
                  width: 2.5,
                  colors: _frameColors,
                  stops: _frameStops,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 单个星粒：按宽度自然缩放，居中
  Widget _sparkleSingle() {
    return Center(
      child: Lottie.asset(
        _sparkleAsset,
        controller: _sparkleCurved,
        fit: BoxFit.fitWidth,
        width: double.infinity,
      ),
    );
  }

  // 上下对角星粒：上方正常贴顶 + 下方旋转180°（点对称/对角）贴底，留出边距
  Widget _sparkleMirrored() {
    return LayoutBuilder(
      builder: (_, c) {
        final inset = c.maxHeight * 0.08; // 上下留距离，不贴边
        return Stack(
          children: [
            Positioned(
              top: inset,
              left: 0,
              right: 0,
              child: Lottie.asset(
                _sparkleAsset,
                controller: _sparkleCurved,
                fit: BoxFit.fitWidth,
                width: double.infinity,
              ),
            ),
            Positioned(
              bottom: inset,
              left: 0,
              right: 0,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateZ(3.1415926), // 旋转180°=对角
                child: Lottie.asset(
                  _sparkleAsset,
                  controller: _sparkleCurved, // 同步播放
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _stripExt(String f) {
    final i = f.lastIndexOf('.');
    return i > 0 ? f.substring(0, i) : f;
  }
}

/// 渐变描边框：外圈渐变、内部镂空（只显示边框，中间透出封面）
class _GradientBorder extends StatelessWidget {
  final double radius;
  final double width;
  final List<Color> colors;
  final List<double> stops;
  const _GradientBorder({
    required this.radius,
    required this.width,
    required this.colors,
    required this.stops,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GradientBorderPainter(radius, width, colors, stops),
      child: const SizedBox.expand(),
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double radius;
  final double width;
  final List<Color> colors;
  final List<double> stops;
  _GradientBorderPainter(this.radius, this.width, this.colors, this.stops);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      Radius.circular(radius - width / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: stops,
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter old) =>
      old.colors != colors || old.width != width || old.radius != radius;
}

/// 模式切换按钮（左上角，汉堡下方）：随机 / 日期 / 人物
class _ModeButton extends StatelessWidget {
  final KeepMode mode;
  final VoidCallback onTap;
  const _ModeButton({required this.mode, required this.onTap});

  IconData get _icon => switch (mode) {
        KeepMode.random => Icons.shuffle,
        KeepMode.date => Icons.schedule,
        KeepMode.person => Icons.person_outline,
      };

  String get _label => switch (mode) {
        KeepMode.random => 'Random',
        KeepMode.date => 'Recent',
        KeepMode.person => 'People',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Keep_C.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: Keep_C.ink, size: 18),
            const SizedBox(width: 6),
            Text(_label,
                style: const TextStyle(
                    color: Keep_C.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  final bool spinning;
  final VoidCallback onTap;
  const _RefreshButton({required this.spinning, required this.onTap});
  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didUpdateWidget(_RefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.spinning && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: RotationTransition(
        turns: _ctrl,
        child: const Icon(Icons.refresh, color: Keep_C.barBg, size: 24),
      ),
    );
  }
}

// ============ 人物模式：字母盲盒（按钮 → 渐隐+爆开 → 字母飞出 → 点字母选人）============
const String _kHeartButtonAsset = 'assets/heart_button.json'; // 持续播放的按钮
const String _kHeartBurstAsset = 'assets/heart_burst.json'; // 点击后爆开

class _BlindboxView extends StatefulWidget {
  final List<String> letters;
  final bool burst; // 是否已爆开（来自父级，绑 share 保活）
  final List<Offset> slots; // 已算好的字母点位（爆过则非空）
  final ValueChanged<List<Offset>> onBurstComplete; // 回传采样好的点位
  final ValueChanged<String> onPickLetter;
  const _BlindboxView({
    super.key,
    required this.letters,
    required this.burst,
    required this.slots,
    required this.onBurstComplete,
    required this.onPickLetter,
  });
  @override
  State<_BlindboxView> createState() => _BlindboxViewState();
}

class _BlindboxViewState extends State<_BlindboxView>
    with TickerProviderStateMixin {
  late final AnimationController _button =
      AnimationController(vsync: this); // 按钮循环
  late final AnimationController _burst =
      AnimationController(vsync: this); // 爆开一次
  final _rng = Random();
  bool _tapped = false; // 已点按钮（按钮淡出 + 播爆开）
  bool _bursting = false; // 爆开动画进行中（显示 heart_burst）
  bool _flying = false; // 字母正在从中心飞出
  bool _atCenter = true; // 字母是否处于中心起飞前
  List<Offset> _slots = [];
  Timer? _afterBurst;

  // 散布参数
  static const double _chip = 56; // 字母标签足迹
  static const double _gap = 14;
  static const double _topPad = 64; // 让出模式按钮
  static const double _bottomPad = 110; // 让出底栏
  static const double _sidePad = 24;
  static const int _tries = 120;
  static const Duration _btnFade = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // 按钮：加载完循环播放
    AssetLottie(_kHeartButtonAsset).load().then((c) {
      if (mounted) {
        _button.duration = c.duration;
        if (!widget.burst && !_tapped) _button.repeat();
      }
    });
    // 爆开：加载时长
    AssetLottie(_kHeartBurstAsset).load().then((c) {
      if (mounted) _burst.duration = c.duration;
    });
    _burst.addStatusListener(_onBurstDone);
    if (widget.burst) {
      // 已爆过（同 share 切回）：直接显示一地字母，不再播按钮/爆开
      _slots = widget.slots;
      _atCenter = false;
    }
  }

  @override
  void dispose() {
    _afterBurst?.cancel();
    _button.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _onTapButton() {
    if (_tapped || widget.burst) return;
    setState(() {
      _tapped = true; // 触发按钮淡出（AnimatedOpacity）
    });
    _button.stop();
    // 按钮完全淡出后，再播爆开（全部消失再爆，不同时）
    _afterBurst?.cancel();
    _afterBurst = Timer(_btnFade, () {
      if (!mounted) return;
      setState(() => _bursting = true);
      _burst.duration ??= const Duration(milliseconds: 1200);
      _burst.forward(from: 0);
    });
  }

  void _onBurstDone(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted) return;
    // 爆开完，停 5ms，再让字母飞出
    _afterBurst?.cancel();
    _afterBurst = Timer(const Duration(milliseconds: 5), _explode);
  }

  void _explode() {
    if (!mounted || _area == null) return;
    final slots = _sampleSlots(_area!, widget.letters.length);
    setState(() {
      _slots = slots;
      _flying = true;
      _bursting = false; // 隐藏爆开层
      _atCenter = true; // 先全在中心
    });
    widget.onBurstComplete(slots); // 通知父级保存（保活）
    // 下一帧放飞
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _atCenter = false);
    });
  }

  Size? _area;

  // 拒绝采样 n 个互不重叠的点位（top-left）
  List<Offset> _sampleSlots(Size a, int n) {
    final rect = Rect.fromLTRB(
        _sidePad, _topPad, a.width - _sidePad, a.height - _bottomPad);
    final maxX = rect.right - _chip;
    final maxY = rect.bottom - _chip;
    final spanX = (maxX - rect.left).clamp(0.0, double.infinity);
    final spanY = (maxY - rect.top).clamp(0.0, double.infinity);
    final out = <Offset>[];
    for (var k = 0; k < n; k++) {
      Offset? best;
      var bestOverlap = 1 << 30;
      var placed = false;
      for (final gap in [_gap, _gap / 2, 0.0]) {
        for (var i = 0; i < _tries; i++) {
          final x = rect.left + _rng.nextDouble() * spanX;
          final y = rect.top + _rng.nextDouble() * spanY;
          final cand = Rect.fromLTWH(x, y, _chip, _chip);
          var ov = 0;
          for (final s in out) {
            if (Rect.fromLTWH(s.dx, s.dy, _chip, _chip)
                .inflate(gap)
                .overlaps(cand)) ov++;
          }
          if (ov == 0) {
            out.add(Offset(x, y));
            placed = true;
            break;
          }
          if (ov < bestOverlap) {
            bestOverlap = ov;
            best = Offset(x, y);
          }
        }
        if (placed) break;
      }
      if (!placed) out.add(best ?? Offset(rect.left, rect.top));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _area = Size(c.maxWidth, c.maxHeight);
        final center = Offset(
            _area!.width / 2 - _chip / 2, _area!.height / 2 - _chip / 2);
        final showButton = !widget.burst && !_flying; // 按钮（点后淡出）
        final showBurst = _bursting; // 爆开层
        final showLetters = widget.burst || _flying;

        return Stack(
          children: [
            // 按钮（循环播放；点击后淡出，淡出完成即从树移除）
            if (showButton && !_bursting)
              Center(
                child: AnimatedOpacity(
                  duration: _btnFade,
                  opacity: _tapped ? 0.0 : 1.0,
                  child: GestureDetector(
                    onTap: _onTapButton,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: Lottie.asset(
                        _kHeartButtonAsset,
                        controller: _button,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            // 爆开层（一次性，居中播放）
            if (showBurst)
              Center(
                child: IgnorePointer(
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Lottie.asset(
                      _kHeartBurstAsset,
                      controller: _burst,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            // 字母（从中心飞到点位）
            if (showLetters)
              for (var i = 0; i < widget.letters.length; i++)
                if (i < _slots.length)
                  AnimatedPositioned(
                    key: ValueKey('letter_${widget.letters[i]}'),
                    duration: const Duration(milliseconds: 720),
                    curve: Curves.easeOutCubic,
                    left: _atCenter ? center.dx : _slots[i].dx,
                    top: _atCenter ? center.dy : _slots[i].dy,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 720),
                      curve: Curves.easeOut,
                      opacity: _atCenter ? 0.0 : 1.0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 720),
                        curve: Curves.easeOutCubic,
                        scale: _atCenter ? 0.4 : 1.0,
                        child: _LetterChip(
                          letter: widget.letters[i],
                          onTap: () => widget.onPickLetter(widget.letters[i]),
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

// 3D 泡泡圆滚滚字母（Baloo2 + 三层立体阴影，复刻 HTML 效果）
class _LetterChip extends StatelessWidget {
  final String letter;
  final VoidCallback onTap;
  const _LetterChip({required this.letter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Center(
          child: Text(
            letter,
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontSize: 40,
              height: 1.0,
              color: Keep_C.ink,
              shadows: [
                // 近层高光（浅）
                Shadow(offset: Offset(2, 2), color: Keep_C.surface),
                // 中层
                Shadow(offset: Offset(4, 4), color: Keep_C.letterMid),
                // 深层投影（带模糊）
                Shadow(
                    offset: Offset(6, 6),
                    blurRadius: 5,
                    color: Keep_C.letterDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 字母下的人物选择浮层：封面网格 + keep 式选中态（单击高亮、双击进入）
class _LetterPeoplePicker extends StatelessWidget {
  final SmbCreds creds;
  final String letter;
  final List<IndexItem> people;
  final Map<String, double> coverAr;
  final ValueChanged<IndexItem> onPick; // 单击直接选中（关浮层并返回）
  const _LetterPeoplePicker({
    required this.creds,
    required this.letter,
    required this.people,
    required this.coverAr,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelBg = Color.alphaBlend(
        Keep_C.surface.withOpacity(0.6), Keep_C.bg);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: panelBg,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height * 0.6),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(letter,
                      style: const TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Keep_C.ink)),
                  const SizedBox(height: 14),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: people.length,
                      itemBuilder: (_, i) {
                        final it = people[i];
                        return _LetterPersonCard(
                          creds: creds,
                          item: it,
                          coverAr: coverAr,
                          onTap: () => onPick(it), // 单击直接进入
                        );
                      },
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

// 浮层里单个人物卡：封面 + 名字，单击直接进入（封面小，无选中态）
class _LetterPersonCard extends StatelessWidget {
  final SmbCreds creds;
  final IndexItem item;
  final Map<String, double> coverAr;
  final VoidCallback onTap;
  const _LetterPersonCard({
    required this.creds,
    required this.item,
    required this.coverAr,
    required this.onTap,
  });

  double? get _ar {
    for (final cand in coverCandidates(item.personPath)) {
      final v = coverAr[cand];
      if (v != null) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: CoverImage(
                  creds: creds,
                  candidates: coverCandidates(item.personPath),
                  fallbackName: item.personName,
                  fallbackColor: Keep_C.surface,
                  fallbackInk: Keep_C.ink,
                  knownAspectRatio: _ar,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(item.personName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Keep_C.ink, fontSize: 12)),
        ],
      ),
    );
  }
}