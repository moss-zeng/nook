import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets_love.dart';
import '../widgets_date.dart';
import '../widgets_input.dart';
import '../widgets_capsule.dart';
import '../state/connection.dart';
import '../smb/smb_client.dart';
import '../models/person.dart';
import '../models/person_meta.dart';
import 'gallery_page.dart';


/// 一个作品条目（本人作品或引用作品）
class WorkItem {
  final String fileName;
  final String playPath;
  final String metaOwnerPath;
  final String metaKey;
  const WorkItem({
    required this.fileName,
    required this.playPath,
    required this.metaOwnerPath,
    required this.metaKey,
  });
}

class PersonPage extends ConsumerStatefulWidget {
  final SmbCreds creds;
  final PersonNode person;
  final String? initialWork;
  final PersonColorSpec spec; // 如何算根色号（活值，随模式/种子变化）
  final bool keepLovedOnly; // 从 keep 进入：只显示 pin/pre（实时按 _person.json 的 love 筛）
  const PersonPage({
    super.key,
    required this.creds,
    required this.person,
    required this.spec,
    this.initialWork,
    this.keepLovedOnly = false,
  });
  @override
  ConsumerState<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends ConsumerState<PersonPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<WorkItem> _works = [];
  PersonMeta _meta = const PersonMeta();
  final Map<String, PersonMeta> _metaCache = {};
  // 收藏写盘防抖
  Timer? _loveSaveTimer;
  final Set<String> _pendingLoveOwners = {};
  WorkItem? _selected;
  List<String> _galleryImages = [];

  // 背景展开度 0~1（1=完全展开，0=收起到顶部条）
  final ScrollController _scroll = ScrollController();
  late final AnimationController _anim;
  double _bgExpand = 1.0;
  double _maxH = 0; // 完全展开高度（build 时按屏算）
  double _lastOffset = 0; // 上次滚动量（增量联动用）
  bool _programScrolling = false; // 程序触发滚动中（点作品定位），不联动
  double _topPad = 0; // 状态栏高度（build 时取）
  final Map<int, GlobalKey> _cardKeys = {};
  GlobalKey _cardKey(int i) => _cardKeys.putIfAbsent(i, () => GlobalKey());
  double get _minH => _topPad + 52; // 收起后只剩顶部条（状态栏+返回按钮）

  String get _personPath => widget.person.path;

  // 根色号（活值）：按 spec 现场算，随配色模式/种子变化
  int get _rootColorIdx =>
      widget.spec.resolve(ref, ref.watch(selectedShareProvider));

  // 作品色号：围绕人物根色号 ±2，按作品文件名稳定取值
  int _workColor(WorkItem w) =>
      Style_C.around(_rootColorIdx, w.fileName, span: 2);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        setState(() => _bgExpand = _anim.value);
      });
    _scroll.addListener(_onScroll);
    // 进入人物页：搜索按钮底色 = 人物色（若初始已选某作品，下面 _load 会改成作品色）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAccent();
    });
    _load();
  }

  // 当前层级强调色：选中作品=作品色，否则人物根色
  int get _accentIdx =>
      _selected != null ? _workColor(_selected!) : _rootColorIdx;
  void _syncAccent() {
    if (widget.keepLovedOnly) return; // 从 keep 进入：不影响 view 搜索按钮
    ref.read(viewAccentProvider.notifier).set(_accentIdx);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _anim.dispose();
    // 兜底：有未写盘的收藏改动，立即补写
    _loveSaveTimer?.cancel();
    if (_pendingLoveOwners.isNotEmpty) _flushLoveSaves();
    super.dispose();
  }

  void _onScroll() {
    if (_anim.isAnimating || _programScrolling) {
      _lastOffset = _scroll.offset;
      return;
    }
    if (_maxH <= _minH) return;
    final delta = _scroll.offset - _lastOffset;
    _lastOffset = _scroll.offset;
    if (delta == 0) return;
    final e = (_bgExpand - delta / (_maxH - _minH)).clamp(0.0, 1.0);
    if ((e - _bgExpand).abs() > 0.0001) {
      setState(() => _bgExpand = e);
    }
  }

  Future<void> _load() async {
    _meta = await PersonMetaRepo.load(widget.creds, _personPath);
    _metaCache[_personPath] = _meta;

    final files = await PersonRepo.listWorks(widget.creds, _personPath);
    final works = <WorkItem>[
      for (final f in files)
        WorkItem(
          fileName: f,
          playPath: '$_personPath/$f',
          metaOwnerPath: _personPath,
          metaKey: f,
        ),
    ];

    final shareName = _personPath.split('/').first;
    for (final ref in _meta.references) {
      final full = '$shareName/$ref';
      final lastSlash = full.lastIndexOf('/');
      if (lastSlash < 0) continue;
      final ownerPath = full.substring(0, lastSlash);
      final file = full.substring(lastSlash + 1);
      works.add(WorkItem(
        fileName: file,
        playPath: full,
        metaOwnerPath: ownerPath,
        metaKey: file,
      ));
      if (!_metaCache.containsKey(ownerPath)) {
        _metaCache[ownerPath] =
            await PersonMetaRepo.load(widget.creds, ownerPath);
      }
    }

    final gallery = await listGalleryImages(widget.creds, _personPath);

    if (!mounted) return;
    setState(() {
      _works = works;
      _galleryImages = gallery;
      _loading = false;
      if (widget.initialWork != null) {
        for (final w in works) {
          if (w.fileName == widget.initialWork) {
            _selected = w;
            break;
          }
        }
      }
    });
    // 若初始选中了某作品，搜索按钮改为作品色
    if (_selected != null) _syncAccent();
  }

  ItemMeta _metaOf(WorkItem w) =>
      (_metaCache[w.metaOwnerPath] ?? const PersonMeta()).itemFor(w.metaKey);

  // 展示用作品列表：从 keep 进入(keepLovedOnly)时只显示 pin/pre，pinnacle 在前、preferred 在后；
  // love 实时取自已加载的 _person.json，取消爱心后退回再进自然消失。
  List<WorkItem> get _displayWorks {
    if (!widget.keepLovedOnly) return _works;
    final loved =
        _works.where((w) => _metaOf(w).love != Love.passable).toList();
    loved.sort((a, b) {
      int rank(Love l) => l == Love.pinnacle ? 0 : 1; // pin 在前
      return rank(_metaOf(a).love) - rank(_metaOf(b).love);
    });
    return loved;
  }

  List<String> _workCover(WorkItem w) =>
      workCoverCandidates(w.metaOwnerPath, w.fileName);

  List<String> get _personCover => coverCandidates(_personPath);

  Future<void> _play(WorkItem w) async {
    await SmbClient.openExternal(widget.creds, w.playPath);
  }

  Future<void> _setLove(WorkItem w, Love love) async {
    final owner = w.metaOwnerPath;
    final ownerMeta = _metaCache[owner] ?? const PersonMeta();
    var newItem = ownerMeta.itemFor(w.metaKey).copyWith(love: love);
    // 变成收藏态(preferred/pinnacle)时刷新 lovedAt；取消(passable)不动
    if (love != Love.passable) {
      newItem = newItem.copyWith(lovedAt: DateTime.now().toIso8601String());
    }
    final newMeta = ownerMeta.withItem(w.metaKey, newItem);
    setState(() => _metaCache[owner] = newMeta); // 内存即时（UI 跟手）
    _scheduleLoveSave(owner); // 防抖写盘（连点只写最后一次）
  }

  // 防抖写盘：停手 800ms 后才把该 owner 的最新 meta 写盘
  void _scheduleLoveSave(String owner) {
    _pendingLoveOwners.add(owner);
    _loveSaveTimer?.cancel();
    _loveSaveTimer = Timer(const Duration(milliseconds: 800), _flushLoveSaves);
  }

  void _flushLoveSaves() {
    final owners = _pendingLoveOwners.toList();
    _pendingLoveOwners.clear();
    for (final owner in owners) {
      final meta = _metaCache[owner];
      if (meta != null) {
        PersonMetaRepo.save(widget.creds, owner, meta); // 不 await，后台写
      }
    }
  }

  Future<void> _setDescription(WorkItem w, String desc) async {
    final owner = w.metaOwnerPath;
    final ownerMeta = _metaCache[owner] ?? const PersonMeta();
    final newItem = ownerMeta.itemFor(w.metaKey).copyWith(description: desc);
    final newMeta = ownerMeta.withItem(w.metaKey, newItem);
    setState(() => _metaCache[owner] = newMeta);
    await PersonMetaRepo.save(widget.creds, owner, newMeta);
  }

  Future<void> _setDate(WorkItem w, String date) async {
    final owner = w.metaOwnerPath;
    final ownerMeta = _metaCache[owner] ?? const PersonMeta();
    final newItem = ownerMeta.itemFor(w.metaKey).copyWith(date: date);
    final newMeta = ownerMeta.withItem(w.metaKey, newItem);
    setState(() => _metaCache[owner] = newMeta);
    await PersonMetaRepo.save(widget.creds, owner, newMeta);
  }

  void _onTapWork(WorkItem w) {
    if (identical(_selected, w)) {
      setState(() => _selected = null);
      _syncAccent(); // 取消选中：回人物色
      _anim.value = _bgExpand;
      _anim.animateTo(1.0, curve: Curves.easeOutCubic);
      return;
    }
    setState(() => _selected = w);
    _syncAccent(); // 选中作品：作品色

    _anim.value = _bgExpand;
    _anim.animateTo(1.0, curve: Curves.easeOutCubic);

    final idx = _works.indexOf(w);
    final key = _cardKey(idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final cardTopY = box.localToGlobal(Offset.zero).dy;
      final delta = cardTopY - _maxH;
      final target = (_scroll.offset + delta).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _programScrolling = true;
      _scroll
          .animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        _programScrolling = false;
        _lastOffset = _scroll.offset;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _topPad = MediaQuery.of(context).padding.top;
    _maxH = MediaQuery.of(context).size.height * 0.5;
    final bgH = _minH + (_maxH - _minH) * _bgExpand;

    // 配色模式/种子变化会让 _accentIdx 变 → build 触发，下一帧同步搜索按钮底色
    // 从 keep 进入(keepLovedOnly)不碰 viewAccent，避免污染 view 搜索按钮
    if (!widget.keepLovedOnly) {
      final accent = _accentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(viewAccentProvider) != accent) {
          ref.read(viewAccentProvider.notifier).set(accent);
        }
      });
    }

    return Scaffold(
      backgroundColor: View_C.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: View_C.accent))
          : Stack(
              children: [
                Positioned.fill(
                  child: _displayWorks.isEmpty
                      ? Padding(
                          padding: EdgeInsets.only(top: _maxH),
                          child: const Center(
                              child: Text('No works',
                                  style: TextStyle(color: View_C.inkSoft))),
                        )
                      : GridView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(20, _maxH + 8, 20, 40),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _displayWorks.length,
                          itemBuilder: (_, i) {
                            final w = _displayWorks[i];
                            return KeyedSubtree(
                              key: _cardKey(i),
                              child: _WorkCard(
                                creds: widget.creds,
                                fileName: w.fileName,
                                coverCandidates: _workCover(w),
                                colorIdx: _workColor(w),
                                love: _metaOf(w).love,
                                selected: identical(w, _selected),
                                onTap: () => _onTapWork(w),
                              ),
                            );
                          },
                        ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: bgH,
                  child: _buildBackground(bgH),
                ),
              ],
            ),
    );
  }

  Widget _buildBackground(double bgH) {
    final w = _selected;
    final bgCandidates = w != null ? _workCover(w) : _personCover;
    // 背景无封面色号：作品用作品色，人物用人物色
    final bgColorIdx = w != null ? _workColor(w) : _rootColorIdx;
    final contentOpacity =
        ((_bgExpand - 0.35) / 0.65).clamp(0.0, 1.0);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(
            key: ValueKey(bgCandidates.join('|')),
            creds: widget.creds,
            candidates: bgCandidates,
            fallbackName: '',
            fallbackColorIdx: bgColorIdx,
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  View_C.bg.withOpacity(0.0),
                  View_C.bg.withOpacity(0.5),
                  View_C.bg,
                ],
                stops: const [0.45, 0.8, 1.0],
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              color: View_C.bg.withOpacity((1.0 - _bgExpand).clamp(0.0, 1.0)),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            left: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_ios_new,
                  color: Style_C.ink(_accentIdx), size: 20),
            ),
          ),
          Positioned(
            left: 20,
            right: 16,
            bottom: 14,
            child: IgnorePointer(
              // 淡出到几乎看不见时，同步禁止点击（否则被收缩栏挡住却仍能误触）
              ignoring: contentOpacity <= 0.05,
              child: Opacity(
                opacity: contentOpacity,
                child: w == null ? _personTitle() : _workInfo(w),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personTitle() {
    final pInk = Style_C.ink(_rootColorIdx);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: _editPersonInfo, // 点人物名 → 编辑别名/备注
            child: Text(
              widget.person.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: pInk, fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_galleryImages.isNotEmpty) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GalleryPage(
                creds: widget.creds,
                personPath: _personPath,
                personName: widget.person.name,
                images: _galleryImages,
              ),
            )),
            child: Icon(Icons.photo_library_outlined,
                color: pInk, size: 22),
          ),
        ],
      ],
    );
  }

  Widget _workInfo(WorkItem w) {
    final meta = _metaOf(w);
    final display = _displayName(w.fileName);
    final wIdx = _workColor(w);
    final wInk = Style_C.ink(wIdx);
    final canRename = w.metaOwnerPath == _personPath; // 仅本人作品可改名
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: canRename ? () => _renameWork(w) : null,
                child: Text(display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: wInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: () => _editDate(w, meta.date ?? ''),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    (meta.date == null || meta.date!.isEmpty)
                        ? 'Add date…'
                        : formatDate(meta.date),
                    style: TextStyle(
                        color: wInk.withOpacity(0.7), fontSize: 12),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _editDescription(w, meta.description ?? ''),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (meta.description == null || meta.description!.isEmpty)
                        ? 'Add description…'
                        : meta.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (meta.description == null ||
                              meta.description!.isEmpty)
                          ? wInk.withOpacity(0.7)
                          : wInk,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoveBadge(
              love: meta.love,
              interactive: true,
              size: 40,
              onChanged: (l) => _setLove(w, l),
            ),
            const SizedBox(width: 22),
            Material(
              color: Style_C.bg(wIdx),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _play(w),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.play_arrow, color: wInk, size: 26),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editDescription(WorkItem w, String initial) async {
    final result = await showColoredInput(
      context,
      colorIdx: _workColor(w),
      title: 'Description',
      initial: initial,
      hint: 'Description',
      maxLines: 5,
    );
    if (result != null) _setDescription(w, result);
  }

  Future<void> _editDate(WorkItem w, String initial) async {
    final result = await showDateEditor(context, initial, colorIdx: _workColor(w));
    if (result != null) _setDate(w, result);
  }

  // 编辑人物别名 / 备注（写 _person.json，保留 items/references）
  Future<void> _editPersonInfo() async {
    final cur = _metaCache[_personPath] ?? _meta;
    final result = await showDialog<_PersonInfoResult>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => _PersonInfoEditor(
        colorIdx: _rootColorIdx,
        initialAliases: cur.aliases,
        initialNotes: cur.notes ?? '',
      ),
    );
    if (result == null) return;
    final updated = PersonMeta(
      name: cur.name,
      aliases: result.aliases,
      notes: result.notes.isEmpty ? null : result.notes,
      items: cur.items,
      references: cur.references,
    );
    setState(() {
      _meta = updated;
      _metaCache[_personPath] = updated;
    });
    await PersonMetaRepo.save(widget.creds, _personPath, updated);
  }

  // 重命名本人作品：改文件名 + 迁移封面 + 迁移 items key + 刷新
  Future<void> _renameWork(WorkItem w) async {
    final ext = () {
      final i = w.fileName.lastIndexOf('.');
      return i >= 0 ? w.fileName.substring(i) : '';
    }();
    final newBase = await showColoredInput(
      context,
      colorIdx: _workColor(w),
      title: 'Rename work',
      initial: _displayName(w.fileName),
      hint: 'New name (without extension)',
    );
    if (newBase == null) return;
    final trimmed = newBase.trim();
    if (trimmed.isEmpty) return;
    final newFile = '$trimmed$ext';
    if (newFile == w.fileName) return;

    final dir = _personPath; // 本人作品在人物目录下
    try {
      // 1. 改视频文件名
      await SmbClient.move(widget.creds, '$dir/${w.fileName}', '$dir/$newFile');
      // 2. 迁移作品封面 .covers/旧名.jpg → .covers/新名.jpg（不存在则忽略）
      try {
        await SmbClient.move(
          widget.creds,
          '$dir/.covers/${w.fileName}.jpg',
          '$dir/.covers/$newFile.jpg',
        );
      } catch (_) {}
      // 3. 迁移 items 里该作品的元数据 key（date/desc/love 不丢）
      final cur = _metaCache[_personPath] ?? _meta;
      if (cur.items.containsKey(w.fileName)) {
        final m = Map<String, ItemMeta>.from(cur.items);
        final itemMeta = m.remove(w.fileName);
        if (itemMeta != null) m[newFile] = itemMeta;
        final updated = PersonMeta(
          name: cur.name,
          aliases: cur.aliases,
          notes: cur.notes,
          items: m,
          references: cur.references,
        );
        _metaCache[_personPath] = updated;
        _meta = updated;
        await PersonMetaRepo.save(widget.creds, _personPath, updated);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Rename failed: $e')));
      return;
    }

    if (!mounted) return;
    setState(() => _selected = null); // 选中项失效，先取消选中
    await _load(); // 重新加载作品列表
  }

  String _displayName(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i > 0 ? fileName.substring(0, i) : fileName;
  }
}

class _WorkCard extends StatefulWidget {
  final SmbCreds creds;
  final String fileName;
  final List<String> coverCandidates;
  final int colorIdx;
  final Love love;
  final bool selected;
  final VoidCallback onTap;
  const _WorkCard({
    required this.creds,
    required this.fileName,
    required this.coverCandidates,
    required this.colorIdx,
    required this.love,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_WorkCard> createState() => _WorkCardState();
}

class _WorkCardState extends State<_WorkCard> {
  bool? _hasCover;

  String get _display {
    final i = widget.fileName.lastIndexOf('.');
    return i > 0 ? widget.fileName.substring(0, i) : widget.fileName;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CoverImage(
                      creds: widget.creds,
                      candidates: widget.coverCandidates,
                      fallbackName: _display,
                      fallbackColorIdx: widget.colorIdx,
                      fit: BoxFit.cover,
                      onResolved: (has) {
                        if (mounted && _hasCover != has) {
                          setState(() => _hasCover = has);
                        }
                      },
                    ),
                  ),
                ),
                if (widget.selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Style_C.ink(widget.colorIdx), width: 2.5),
                      ),
                    ),
                  ),
                if (widget.love != Love.passable)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: LoveBadge(love: widget.love, size: 40),
                  ),
              ],
            ),
          ),
          // 仅"有封面"时显示下方小字名（作品随机色）；无封面靠色块上的名
          if (_hasCover == true) ...[
            const SizedBox(height: 8),
            Text(
              _display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Style_C.ink(widget.colorIdx),
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}

/// 人物别名/备注编辑结果
class _PersonInfoResult {
  final List<String> aliases;
  final String notes;
  const _PersonInfoResult(this.aliases, this.notes);
}

/// 编辑人物别名 + 备注。别名每行一个；空行忽略。
class _PersonInfoEditor extends StatefulWidget {
  final int colorIdx;
  final List<String> initialAliases;
  final String initialNotes;
  const _PersonInfoEditor({
    required this.colorIdx,
    required this.initialAliases,
    required this.initialNotes,
  });
  @override
  State<_PersonInfoEditor> createState() => _PersonInfoEditorState();
}

class _PersonInfoEditorState extends State<_PersonInfoEditor> {
  late List<String> _aliases = [...widget.initialAliases];
  bool _deleting = false; // 别名删除动画播放中，+ 不可选中
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.initialNotes);
  final FocusNode _notesFocus = FocusNode();

  @override
  void dispose() {
    _notesCtrl.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  bool _closed = false;
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(
        context, _PersonInfoResult(_aliases, _notesCtrl.text.trim()));
  }

  Future<void> _addAlias() async {
    final v = await showColoredInput(
      context,
      colorIdx: widget.colorIdx,
      title: 'Add alias',
      hint: 'Alias',
    );
    if (v == null) return;
    final t = v.trim();
    if (t.isEmpty || _aliases.contains(t)) return;
    setState(() => _aliases.add(t));
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.alphaBlend(
        Style_C.bg(widget.colorIdx).withOpacity(0.5), View_C.surface);
    final ink = Style_C.ink(widget.colorIdx);

    return Stack(
      children: [
        // 点外侧：直接关闭并保存（输完即走）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aliases',
                          style: TextStyle(
                              color: ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      // 别名胶囊 + 号加新；长按胶囊变灰抖动，双击删+poof
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final a in _aliases)
                            ShakeDeletableCapsule(
                              key: ValueKey(a),
                              label: a,
                              colorIdx: widget.colorIdx,
                              onDeleteStart: () =>
                                  setState(() => _deleting = true),
                              onDeleted: () => setState(() {
                                _aliases.remove(a);
                                _deleting = false;
                              }),
                            ),
                          // + 胶囊（删除动画期间仅禁用点击，不变淡）
                          GestureDetector(
                            onTap: _deleting ? null : _addAlias,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 9),
                              decoration: BoxDecoration(
                                color: Style_C.bg(widget.colorIdx)
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: ink.withOpacity(0.4)),
                              ),
                              child: Icon(Icons.add, size: 16, color: ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Notes',
                          style: TextStyle(
                              color: ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      // notes 融入面板（无独立色块）
                      TextField(
                        controller: _notesCtrl,
                        focusNode: _notesFocus,
                        maxLines: 5,
                        minLines: 1,
                        cursorColor: ink,
                        style: const TextStyle(
                            color: View_C.ink, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Notes',
                          hintStyle: const TextStyle(color: View_C.inkSoft),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: ink.withOpacity(0.25)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}