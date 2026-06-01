import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets_love.dart';
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

class PersonPage extends StatefulWidget {
  final SmbCreds creds;
  final PersonNode person;
  final String? initialWork;
  const PersonPage({
    super.key,
    required this.creds,
    required this.person,
    this.initialWork,
  });
  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<WorkItem> _works = [];
  PersonMeta _meta = const PersonMeta();
  final Map<String, PersonMeta> _metaCache = {};
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
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _anim.dispose();
    super.dispose();
  }

  // 增量式联动：上滑减少展开度、下滑增加。任意位置都平滑收起，
  // 与滚动绝对位置无关（避免点作品展开后再滑动突变）。
  void _onScroll() {
    // 程序触发的滚动（点作品定位）期间，不联动收起背景
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
  }

  ItemMeta _metaOf(WorkItem w) =>
      (_metaCache[w.metaOwnerPath] ?? const PersonMeta()).itemFor(w.metaKey);

  List<String> _workCover(WorkItem w) => [
        '${w.metaOwnerPath}/.covers/${w.fileName}.jpg',
        '$_personPath/_cover.jpg',
      ];

  List<String> get _personCover => ['$_personPath/_cover.jpg'];

  Future<void> _play(WorkItem w) async {
    await SmbClient.openExternal(widget.creds, w.playPath);
  }

  Future<void> _setLove(WorkItem w, Love love) async {
    final owner = w.metaOwnerPath;
    final ownerMeta = _metaCache[owner] ?? const PersonMeta();
    final newItem = ownerMeta.itemFor(w.metaKey).copyWith(love: love);
    final newMeta = ownerMeta.withItem(w.metaKey, newItem);
    setState(() => _metaCache[owner] = newMeta);
    await PersonMetaRepo.save(widget.creds, owner, newMeta);
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

  // 点作品：toggle。展开背景(动画)+滚动让该作品顶部贴背景下缘(完整露出)。
  void _onTapWork(WorkItem w) {
    if (identical(_selected, w)) {
      // 再次点同一作品：收起
      _programScrolling = false;
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset); // 停掉残余滚动动画
      setState(() => _selected = null);
      _anim.value = _bgExpand;
      _anim.animateTo(0.0, curve: Curves.easeOutCubic);
      return;
    }
    setState(() => _selected = w);

    // 背景展开动画
    _anim.value = _bgExpand;
    _anim.animateTo(1.0, curve: Curves.easeOutCubic);

    // 用被点卡片的真实渲染位置精确定位：让它顶部滚到背景下缘(_maxH)
    final idx = _works.indexOf(w);
    final key = _cardKey(idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      // 卡片顶部在屏幕上的 y
      final cardTopY = box.localToGlobal(Offset.zero).dy;
      // 目标：卡片顶部对齐到 _maxH（背景完全展开后的下缘）
      final delta = cardTopY - _maxH - 100;
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

    return Scaffold(
      backgroundColor: C.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : Stack(
              children: [
                // 作品网格：顶部留出最大背景高度的空白，背景盖在上方
                Positioned.fill(
                  child: _works.isEmpty
                      ? Padding(
                          padding: EdgeInsets.only(top: _maxH),
                          child: const Center(
                              child: Text('No works',
                                  style: TextStyle(color: C.inkSoft))),
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
                          itemCount: _works.length,
                          itemBuilder: (_, i) {
                            final w = _works[i];
                            return KeyedSubtree(
                              key: _cardKey(i),
                              child: _WorkCard(
                                creds: widget.creds,
                                fileName: w.fileName,
                                coverCandidates: _workCover(w),
                                love: _metaOf(w).love,
                                selected: identical(w, _selected),
                                onTap: () => _onTapWork(w),
                              ),
                            );
                          },
                        ),
                ),
                // 背景区（盖在网格上方，高度随 _bgExpand 变化）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: bgH,
                  child: _buildBackground(bgH),
                ),
                // 返回按钮：最顶层，不受背景封面加载影响，始终可点
                Positioned(
                  top: _topPad + 2,
                  left: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: C.ink, size: 20),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBackground(double bgH) {
    final w = _selected;
    final bgCandidates = w != null ? _workCover(w) : _personCover;
    // 内容透明度：背景收起时淡出文字
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
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  C.bg.withOpacity(0.0),
                  C.bg.withOpacity(0.5),
                  C.bg,
                ],
                stops: const [0.45, 0.8, 1.0],
              ),
            ),
          ),
          // 收起时整体渐变白，视觉上"收"没（expand=0 全白融入页面）
          IgnorePointer(
            child: Container(
              color: C.bg.withOpacity((1.0 - _bgExpand).clamp(0.0, 1.0)),
            ),
          ),
          // 浮层文字（底部）：人物名 或 作品信息
          Positioned(
            left: 20,
            right: 16,
            bottom: 14,
            child: Opacity(
              opacity: contentOpacity,
              child: w == null ? _personTitle() : _workInfo(w),
            ),
          ),
        ],
      ),
    );
  }

  // 人物名 + gallery 入口
  Widget _personTitle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.person.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: C.ink, fontSize: 22, fontWeight: FontWeight.w700),
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
            child: const Icon(Icons.photo_library_outlined,
                color: C.accent, size: 22),
          ),
        ],
      ],
    );
  }

  // 作品信息：左 作品名/日期/描述，右 心心+播放（同高）
  Widget _workInfo(WorkItem w) {
    final meta = _metaOf(w);
    final display = _displayName(w.fileName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作品名：人物名同款大字
              Text(display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: C.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              // 日期：小灰字 / Add date 占位
              GestureDetector(
                onTap: () => _editDate(w, meta.date ?? ''),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    (meta.date == null || meta.date!.isEmpty)
                        ? 'Add date…'
                        : meta.date!,
                    style: const TextStyle(color: C.inkSoft, fontSize: 12),
                  ),
                ),
              ),
              // 描述
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
                          ? C.inkSoft
                          : C.ink,
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
        // 右侧：心心 + 播放，垂直居中对齐
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoveBadge(
              love: meta.love,
              interactive: true,
              size: 28,
              onChanged: (l) => _setLove(w, l),
            ),
            const SizedBox(width: 10),
            Material(
              color: C.accent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _play(w),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      Icon(Icons.play_arrow, color: Colors.white, size: 26),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editDescription(WorkItem w, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Description'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter description'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) _setDescription(w, result);
  }

  Future<void> _editDate(WorkItem w, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Date'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 2023-06-21'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) _setDate(w, result);
  }

  String _displayName(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i > 0 ? fileName.substring(0, i) : fileName;
  }
}

class _WorkCard extends StatelessWidget {
  final SmbCreds creds;
  final String fileName;
  final List<String> coverCandidates;
  final Love love;
  final bool selected;
  final VoidCallback onTap;
  const _WorkCard({
    required this.creds,
    required this.fileName,
    required this.coverCandidates,
    required this.love,
    required this.selected,
    required this.onTap,
  });

  String get _display {
    final i = fileName.lastIndexOf('.');
    return i > 0 ? fileName.substring(0, i) : fileName;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                      creds: creds,
                      candidates: coverCandidates,
                      fallbackName: _display,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: C.accent, width: 2.5),
                      ),
                    ),
                  ),
                if (love != Love.passable)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: LoveBadge(love: love, size: 22),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: C.ink, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}