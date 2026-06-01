import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../widgets.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../models/styles.dart';
import 'people_page.dart';
import 'text_page.dart';

const _videoExt = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'rmvb', 'rm'
};
bool _isVideo (String name) {
  final i = name.lastIndexOf('.');
  if (i <0) return false;
  return _videoExt.contains(name.substring(i + 1).toLowerCase());
}

bool _ignoredTop (String name) =>
    name.startsWith('_') || name.startsWith('.') || name == '_blindbox';

class ViewPage extends ConsumerStatefulWidget {
  const ViewPage ({super.key});
  @override
  ConsumerState<ViewPage> createState () => _ViewPageState ();
}

class _ViewPageState extends ConsumerState<ViewPage> {
  String? _loadedShare;
  bool _loading = false;
  StylesConfig? _config;
  bool _resolved = false;

  @override
  Widget build (BuildContext context) {
    final share = ref.watch(selectedShareProvider);
    final conn = ref.watch(connectionProvider);
    final refresh = ref.watch(viewRefreshProvider);

    if (share == null || conn.creds == null) {
      return const Center (
        child: Text ('Pick a share in Link',
            style: TextStyle (color: C.inkSoft, fontSize: 16)),
      );
}

    if (_loadedShare != share && !_loading) {
      _loadedShare = share;
      _resolved = false;
      _loadMode (conn.creds!, share);
}

    if (!_resolved) {
      return const Center (child: CircularProgressIndicator (color: C.accent));
}

    if (_config != null) {
      // 特定模式：清除任何锁定（特定模式不能移动）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(pendingMoveProvider) != null) {
          ref.read(pendingMoveProvider.notifier).clear();
}
      });
      return Column (
        children: [
          // 左上 模式切换（汉堡下方）、右上盲盒
          Padding (
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row (
              children: [
                IconButton (
                  onPressed: () => _openInbox (conn.creds!, share),
                  icon: const Icon (Icons.swap_horiz,
                      color: C.inkSoft, size: 22),
                  tooltip: 'Browse files',
                ),
                const Spacer (),
                IconButton (
                  onPressed: () => _openBlindbox (conn.creds!, share),
                  icon: const Icon (Icons.inbox_outlined,
                      color: C.inkSoft, size: 22),
                  tooltip: 'Blindbox',
                ),
],
            ),
          ),
          Expanded (
            child: _SpecificView (
              key: ValueKey ('specific_$refresh'),
              creds: conn.creds!,
              share: share,
              config: _config!,
              onConfigChanged: (cfg) => setState (() => _config = cfg),
            ),
          ),
        ],
      );
    }

    // 普通 share（无 styles.json）：内嵌根目录浏览（非 inbox）
    return _DirBrowser (
      creds: conn.creds!,
      dirPath: share,
      isInbox: false,
      isRoot: true,
);
  }

  // inbox：push 一个普通浏览根目录（带 inbox 标记）
  void _openInbox (SmbCreds c, String share) {
    Navigator.of(context).push(MaterialPageRoute (
      builder: (_) => _DirBrowserScaffold (
        creds: c,
        dirPath: share,
        isInbox: true,
        isRoot: true,
),
    ));
}

  void _openBlindbox (SmbCreds c, String share) {
    Navigator.of(context).push(MaterialPageRoute (
      builder: (_) => BlindboxPage (creds: c, share: share),
    ));
}

  Future<void> _loadMode (SmbCreds c, String share) async {
    setState (() => _loading = true);
    final cfg = await StylesRepo.load(c, share);
    if (!mounted) return;
    setState (() {
      _config = cfg;
      _resolved = true;
      _loading = false;
});
  }
}

// ============ 特定模式 ============
class _SpecificView extends StatelessWidget {
  final SmbCreds creds;
  final String share;
  final StylesConfig config;
  final ValueChanged<StylesConfig> onConfigChanged;
  const _SpecificView ({
    super.key,
    required this.creds,
    required this.share,
    required this.config,
    required this.onConfigChanged,
});

  String _nextField () {
    final used = config.groups.map((g) => g.field).toSet();
    var i = 1;
    while (used.contains('styles$i')) {
      i++;
}
    return'styles$i';
  }

  Future<void> _addGroup () async {
    final newGroups = [...config.groups, StyleGroup (_nextField (), <String>[])];
    final newConfig = StylesConfig (newGroups);
    await StylesRepo.save(creds, share, newConfig);
    onConfigChanged (newConfig);
}

  Future<void> _deleteGroup (int index) async {
    final newGroups = [...config.groups]..removeAt(index);
    final newConfig = StylesConfig (newGroups);
    await StylesRepo.save(creds, share, newConfig);
    onConfigChanged (newConfig);
}

  @override
  Widget build (BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: config.groups.length + 1,
      separatorBuilder: (_, __) => const SizedBox (height: 20),
      itemBuilder: (_, i) {
        if (i == config.groups.length) {
          return Padding (
            padding: const EdgeInsets.only(top: 8),
            child: Center (
                child: SoftSquareButton (icon: Icons.add, onTap: _addGroup)),
          );
}
        return _StyleGroupBlock (
          creds: creds,
          share: share,
          config: config,
          groupIndex: i,
          onConfigChanged: onConfigChanged,
          onDeleteGroup: () => _deleteGroup (i),
        );
      },
    );
  }
}

class _StyleGroupBlock extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  final StylesConfig config;
  final int groupIndex;
  final ValueChanged<StylesConfig> onConfigChanged;
  final VoidCallback onDeleteGroup;
  const _StyleGroupBlock ({
    required this.creds,
    required this.share,
    required this.config,
    required this.groupIndex,
    required this.onConfigChanged,
    required this.onDeleteGroup,
});
  @override
  State<_StyleGroupBlock> createState () => _StyleGroupBlockState ();
}

class _StyleGroupBlockState extends State<_StyleGroupBlock> {
  @override
  Widget build (BuildContext context) {
    // 每次 build 重新随机，切回页面/重建时标签位置变化
    final seed = DateTime.now().microsecondsSinceEpoch ^
        widget.groupIndex.hashCode;
    final group = widget.config.groups[widget.groupIndex];
    final isEmpty = group.styles.isEmpty;

    return GestureDetector (
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditor (context),
      child: AspectRatio (
        aspectRatio: 1, // 正方形区域
        child: Container (
          decoration: BoxDecoration (
            color: C.barBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack (
            children: [
              // 标签层
              if (isEmpty)
                const Center (
                  child: Text ('Tap to add styles',
                      style: TextStyle (color: C.inkSoft, fontSize: 13)),
                )
              else
                LayoutBuilder (
                  builder: (context, constraints) {
                    return _ScatteredTags (
                      labels: group.styles,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      seed: seed,
                      onTapLabel: _openStyle,
);
},
                ),
              // 空组右上角 × 删除
              if (isEmpty)
                Positioned (
                  top: 8,
                  right: 8,
                  child: GestureDetector (
                    onTap: widget.onDeleteGroup,
                    child: Container (
                      padding: const EdgeInsets.all(4),
                      child: const Icon (Icons.close,
                          size: 20, color: C.inkSoft),
                    ),
                  ),
                ),
],
          ),
        ),
      ),
    );
  }

  Future<void> _openStyle (String s) async {
    await Navigator.of(context).push(MaterialPageRoute (
      builder: (_) => PeoplePage (
        creds: widget.creds,
        stylePath: '${widget.share}/$s',
        styleName: s,
),
    ));
    if (mounted) setState (() {}); 
  }

  Future<void> _openEditor (BuildContext context) async {
    final entries = await SmbClient.list(widget.creds, widget.share);
    final registered = widget.config.allRegistered;
    final candidates = entries
        .where((e) => e.isDir && !_ignoredTop (e.name))
        .map((e) => e.name)
        .where((n) => !registered.contains(n))
        .toList();
    final current = widget.config.groups[widget.groupIndex].styles;

    if (!context.mounted) return;
    final result = await showDialog <List<String>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => _GroupEditor (
        creds: widget.creds,
        share: widget.share,
        current: current,
        candidates: candidates,
),
    );
    if (result == null) return;

    final newGroups = <StyleGroup>[];
    for (var i = 0; i <widget.config.groups.length; i++) {
      final g = widget.config.groups[i];
      newGroups.add(
          i == widget.groupIndex ? StyleGroup (g.field, result) : g);
}
    final newConfig = StylesConfig (newGroups);
    await StylesRepo.save(widget.creds, widget.share, newConfig);
    widget.onConfigChanged(newConfig);
  }
}

/// 在固定区域内随机散布标签，做防重叠尝试；塞不下则退回顺序流式排列
class _ScatteredTags extends StatelessWidget {
  final List<String> labels;
  final double width;
  final double height;
  final int seed;
  final ValueChanged<String> onTapLabel;
  const _ScatteredTags ({
    required this.labels,
    required this.width,
    required this.height,
    required this.seed,
    required this.onTapLabel,
});

  // 估算标签宽高（与 _StyleTag 内 padding/字号匹配）
  Size _estimate (String label) {
    final text = '#$label';
    // 粗略：每个字符宽度按字号估，中文偏宽
    final charW = 15.0;
    final w = text.length * charW + 32; // 含左右 padding
    return Size (w, 38);
}

  @override
  Widget build (BuildContext context) {
    final rng = Random (seed);
    final placed = <Rect>[];
    final positioned = <Widget>[];
    const pad = 8.0;
    bool overflowFail = false;

    for (final label in labels) {
      final size = _estimate (label);
      // 标签若比区域还宽，直接判失败退回
      if (size.width> width - pad * 2 || size.height > height - pad * 2) {
        overflowFail = true;
        break;
}
      Rect? spot;
      for (var attempt = 0; attempt <40; attempt++) {
        final maxX = width - size.width - pad;
        final maxY = height - size.height - pad;
        final x = pad + rng.nextDouble() * (maxX - pad).clamp(0, maxX);
        final y = pad + rng.nextDouble() * (maxY - pad).clamp(0, maxY);
        final r = Rect.fromLTWH(x, y, size.width, size.height);
        final overlaps = placed.any((p) => p.inflate(4).overlaps(r));
        if (!overlaps) {
          spot = r;
          break;
}
      }
      if (spot == null) {
        overflowFail = true;
        break;
}
      placed.add(spot);
      positioned.add(Positioned (
        left: spot.left,
        top: spot.top,
        child: _StyleTag (label: label, onTap: () => onTapLabel (label)),
      ));
    }

    if (overflowFail) {
      // 退回：顺序流式排列
      return Padding (
        padding: const EdgeInsets.all(12),
        child: Wrap (
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final l in labels)
              _StyleTag (label: l, onTap: () => onTapLabel (l)),
],
        ),
      );
}

    return Stack (children: positioned);
  }
}

class _StyleTag extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StyleTag ({required this.label, required this.onTap});
  @override
  Widget build (BuildContext context) {
    return Material (
      color: C.accentSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell (
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container (
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration (
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.accent.withOpacity(0.25)),
          ),
          child: Text ('#$label',
              style: const TextStyle (
                  color: C.accent, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
    );
}
}

// 风格组编辑器：居中浮层，2:6:2，文件夹卡片网格，选中 = 蓝描边 + 左上勾
class _GroupEditor extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  final List<String> current;
  final List<String> candidates;
  const _GroupEditor ({
    required this.creds,
    required this.share,
    required this.current,
    required this.candidates,
});
  @override
  State<_GroupEditor> createState () => _GroupEditorState ();
}

class _GroupEditorState extends State<_GroupEditor> {
  late Set<String> _selected;
  @override
  void initState () {
    super.initState();
    _selected = widget.current.toSet();
}

  @override
  Widget build (BuildContext context) {
    final size = MediaQuery.of(context).size;
    final all = <String>[...widget.current, ...widget.candidates];

    return Center (
      child: Padding (
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material (
          color: C.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding (
            padding: const EdgeInsets.all(20),
            child: Column (
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text ('Edit styles',
                    style: TextStyle (
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: C.ink)),
                const SizedBox (height: 16),
                // 固定高度的内容区（约屏幕高度的一部分），可滚动
                SizedBox (
                  height: size.height * 0.42,
                  child: all.isEmpty
                      ? const Center (
                          child: Text ('No folders available',
                              style: TextStyle (color: C.inkSoft)))
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount (
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.0,
),
                          itemCount: all.length,
                          itemBuilder: (_, i) {
                            final name = all [i];
                            final on = _selected.contains(name);
                            return _FolderPick (
                              name: name,
                              selected: on,
                              onTap: () => setState (() {
                                on
                                    ? _selected.remove(name)
                                    : _selected.add(name);
}),
                            );
                          },
                        ),
                ),
                const SizedBox (height: 16),
                SizedBox (
                  width: double.infinity,
                  child: TextButton (
                    onPressed: () {
                      final out = <String>[
                        ...widget.current.where(_selected.contains),
                        ...widget.candidates.where(_selected.contains),
];
                      Navigator.pop(context, out);
},
                    style: TextButton.styleFrom(
                      backgroundColor: C.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder (
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text ('Done',
                        style: TextStyle (fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 编辑器里的文件夹卡片：文件夹图标 + 名字，选中 = 蓝描边 + 左上勾
class _FolderPick extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _FolderPick ({
    required this.name,
    required this.selected,
    required this.onTap,
});
  @override
  Widget build (BuildContext context) {
    return GestureDetector (
      onTap: onTap,
      child: Stack (
        children: [
          Positioned.fill(
            child: Container (
              decoration: BoxDecoration (
                color: C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? C.accent : C.line,
                  width: selected ? 2 : 1,
),
              ),
              padding: const EdgeInsets.all(10),
              child: Column (
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon (Icons.folder_outlined,
                      color: C.accent, size: 34),
                  const SizedBox (height: 6),
                  Text (
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle (
                        color: C.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
],
              ),
            ),
          ),
          if (selected)
            const Positioned (
              top: 6,
              left: 6,
              child: Icon (Icons.check_circle, color: C.accent, size: 18),
            ),
        ],
      ),
    );
}
}

// ============ 普通模式 ============
// inbox 模式的浏览：带 Scaffold + 顶部 Exit（一键回特定模式）
class _DirBrowserScaffold extends StatelessWidget {
  final SmbCreds creds;
  final String dirPath;
  final bool isInbox;
  final bool isRoot;
  const _DirBrowserScaffold ({
    required this.creds,
    required this.dirPath,
    required this.isInbox,
    this.isRoot = false,
});
  @override
  Widget build (BuildContext context) {
    return Scaffold (
      backgroundColor: C.bg,
      resizeToAvoidBottomInset: false,
      body: SafeArea (
        child: _DirBrowser (
            creds: creds, dirPath: dirPath, isInbox: isInbox, isRoot: isRoot),
      ),
    );
}
}

// 单目录浏览：点文件夹 push 下一层，返回 = pop（与其他页面一致）
class _DirBrowser extends ConsumerStatefulWidget {
  final SmbCreds creds;
  final String dirPath; // 相对 share 根的完整路径（含 share）
  final bool isInbox; // 是否 inbox 模式（决定显示 Exit）
  final bool isRoot; // 是否 ViewPage 内嵌的根（普通 share 根，无返回）
  const _DirBrowser ({
    required this.creds,
    required this.dirPath,
    required this.isInbox,
    this.isRoot = false,
});
  @override
  ConsumerState<_DirBrowser> createState () => _DirBrowserState ();
}

class _DirBrowserState extends ConsumerState<_DirBrowser> {
  List<SmbEntry> _entries = [];
  bool _loading = true;
  SmbEntry? _selecting;

  String get _dir => widget.dirPath;
  // 顶层路径（用于显示）：取末段
  String get _title {
    final i = _dir.lastIndexOf('/');
    return i >= 0 ? _dir.substring(i + 1) : _dir;
}

  @override
  void initState () {
    super.initState();
    _load ();
}

  Future<void> _load () async {
    setState (() => _loading = true);
    final list = await SmbClient.list(widget.creds, _dir);
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
});
    if (!mounted) return;
    setState (() {
      _entries = list;
      _loading = false;
});
  }

  void _enter (String name) {
    if (_selecting != null) return;
    Navigator.of(context).push(MaterialPageRoute (
      builder: (_) => _DirBrowserScaffold (
        creds: widget.creds,
        dirPath: '$_dir/$name',
        isInbox: widget.isInbox,
),
    ));
}

  void _openFile(String name) {
    if (isTextFile(name)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextPage(
          creds: widget.creds,
          filePath: '$_dir/$name',
          fileName: name,
        ),
      ));
    } else {
      SmbClient.openExternal(widget.creds, '$_dir/$name');
    }
  }

  void _longPress (SmbEntry e) {
    HapticFeedback.mediumImpact();
    setState (() => _selecting = e);
}

  void _cancelSelect () => setState (() => _selecting = null);

  Future<void> _doRename (SmbEntry e) async {
    final ctrl = TextEditingController (text: e.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog (
        backgroundColor: C.surface,
        title: const Text ('Rename'),
        content: TextField (controller: ctrl, autofocus: true),
        actions: [
          TextButton (
              onPressed: () => Navigator.pop(dctx),
              child: const Text ('Cancel')),
          TextButton (
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text ('Save')),
],
      ),
    );
    if (newName == null || newName.isEmpty || newName == e.name) {
      _cancelSelect ();
      return;
}
    try {
      await SmbClient.move(widget.creds, '$_dir/${e.name}', '$_dir/$newName');
      _cancelSelect ();
      _load ();
    } catch (err) {
      _showError ('$err');
      _cancelSelect ();
}
  }

  void _startMove (SmbEntry e) {
    ref.read(pendingMoveProvider.notifier).lock(PendingMove (
          fromPath: '$_dir/${e.name}',
          name: e.name,
          isDir: e.isDir,
));
    setState (() => _selecting = null);
  }

  Future<void> _paste (PendingMove pm) async {
    final target = '$_dir/${pm.name}';
    if (target == pm.fromPath) {
      ref.read(pendingMoveProvider.notifier).clear();
      return;
}
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog (
        backgroundColor: C.surface,
        content: Text ('Move "${pm.name}" here?'),
        actions: [
          TextButton (
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text ('Cancel')),
          TextButton (
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text ('Move')),
],
      ),
    );
    if (ok != true) return;
    try {
      await SmbClient.move(widget.creds, pm.fromPath, target);
      ref.read(pendingMoveProvider.notifier).clear();
      _load ();
} catch (err) {
      _showError ('$err');
}
  }

  void _showError (String msg) {
    showDialog (
      context: context,
      builder: (dctx) => AlertDialog (
        backgroundColor: C.surface,
        title: const Text ('Failed'),
        content: Text (msg),
        actions: [
          TextButton (
              onPressed: () => Navigator.pop(dctx),
              child: const Text ('OK')),
],
      ),
    );
}

  // Exit：一键回特定模式（pop 掉所有 push 的浏览页，无逐页动画）
  void _exitInbox () {
    ref.read(pendingMoveProvider.notifier).clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
}

  @override
  Widget build (BuildContext context) {
    final pending = ref.watch(pendingMoveProvider);

    return PopScope (
      canPop: !widget.isRoot,
      child: Stack (
      children: [
        Column (
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏
            Padding (
              padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
              child: Row (
                children: [
                  if (_selecting != null)
                    IconButton (
                      onPressed: _cancelSelect,
                      icon: const Icon (Icons.close, size: 20, color: C.ink),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints (),
                    )
                  else
                    IconButton (
                      onPressed: widget.isRoot
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: Icon (Icons.arrow_back_ios_new,
                          size: 18,
                          color: widget.isRoot ? C.inkSoft.withOpacity(0.3) : C.ink),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints (),
                    ),
                    const SizedBox (width: 12),
                  Expanded (
                    child: Text (
                      _title,
                      style: const TextStyle (color: C.ink, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // inbox 模式：任意层都有 Exit
                  if (widget.isInbox && _selecting == null)
                    TextButton (
                      onPressed: _exitInbox,
                      child: const Text ('Exit',
                          style: TextStyle (color: C.accent, fontSize: 13)),
                    ),
],
              ),
            ),
            Expanded (
              child: _loading
                  ? const Center (
                      child: CircularProgressIndicator (color: C.accent))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) =>
                          const Divider (color: C.line, height: 1),
                  itemBuilder: (_, i) {
                        final e = _entries[i];
                        final isText = !e.isDir && isTextFile(e.name);
                        final isVid = !e.isDir && _isVideo(e.name);
                        final isSel = identical(e, _selecting);
                        return Container(
                          decoration: isSel
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: C.accent, width: 2),
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
                                      : (isText
                                          ? Icons.description_outlined
                                          : Icons
                                              .insert_drive_file_outlined)),
                              color: e.isDir ? C.accent : C.inkSoft,
                            ),
                            title: Text(e.name,
                                style: const TextStyle(
                                    color: C.ink, fontSize: 14)),
                            onTap: _selecting != null
                                ? null
                                : (e.isDir
                                    ? () => _enter(e.name)
                                    : () => _openFile(e.name)),
                            onLongPress: () => _longPress(e),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        // 底部操作条
        if (_selecting != null)
          Positioned (
            left: 16,
            right: 16,
            bottom: 92,
            child: _BottomActionBar (
              children: [
                _ActionChip (
                    label: 'Rename',
                    icon: Icons.drive_file_rename_outline,
                    onTap: () => _doRename (_selecting!)),
                _ActionChip (
                    label: 'Move',
                    icon: Icons.drive_file_move_outline,
                    onTap: () => _startMove (_selecting!)),
],
            ),
          )
        else if (pending != null)
          Positioned (
            left: 16,
            right: 16,
            bottom: 92,
            child: _BottomActionBar (
              children: [
                _ActionChip (
                    label: 'Cancel',
                    icon: Icons.close,
                    onTap: () =>
                        ref.read(pendingMoveProvider.notifier).clear()),
                _ActionChip (
                    label: 'Paste',
                    icon: Icons.content_paste,
                    highlight: true,
                    enabled: _dir !=
                        pending.fromPath.substring(
                            0, pending.fromPath.lastIndexOf('/')),
                    onTap: () => _paste (pending)),
],
            ),
          ),
      ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final List<Widget> children;
  const _BottomActionBar ({required this.children});
  @override
  Widget build (BuildContext context) {
    return Container (
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration (
        color: C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.line),
        boxShadow: [
          BoxShadow (
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset (0, 4),
          ),
],
      ),
      child: Row (
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
  const _ActionChip ({
    required this.label,
    required this.icon,
    required this.onTap,
    this.highlight = false,
    this.enabled = true,
});
  @override
  Widget build (BuildContext context) {
    final color = !enabled
        ? C.inkSoft.withOpacity(0.35)
        : (highlight ? C.accent : C.ink);
    return Expanded (
      child: InkWell (
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding (
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column (
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon (icon, color: color, size: 22),
              const SizedBox (height: 4),
              Text (label,
                  style: TextStyle (
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

// ============ 盲盒：平铺所有视频 ============
class BlindboxPage extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  const BlindboxPage ({super.key, required this.creds, required this.share});
  @override
  State<BlindboxPage> createState () => _BlindboxPageState ();
}

class _BlindboxPageState extends State<BlindboxPage> {
  List<String> _videos = []; // 相对 share 根的完整路径
  bool _loading = true;

  String get _root => '${widget.share}/_blindbox';

  @override
  void initState () {
    super.initState();
    _scan ();
  }

  // 递归压平盲盒下所有视频
  Future<void> _scan () async {
    final found = <String>[];
    await _walk (_root, found);
    if (!mounted) return;
    setState (() {
      _videos = found;
      _loading = false;
    });
  }

  Future<void> _walk (String path, List<String> out) async {
    List<SmbEntry> entries;
    try {
      entries = await SmbClient.list(widget.creds, path);
    } catch (_) {
      return;
    }
    for (final e in entries) {
      if (e.isDir) {
        await _walk ('$path/${e.name}', out);
      } else if (_isVideo (e.name)) {
        out.add('$path/${e.name}');
      }
    }
  }

  @override
  Widget build (BuildContext context) {
    return Scaffold (
      backgroundColor: C.bg,
      appBar: AppBar (
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton (
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon (Icons.arrow_back_ios_new, color: C.ink, size: 20),
        ),
        title: const Text ('Blindbox',
            style: TextStyle (
                color: C.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : _videos.isEmpty
              ? const Center(
                  child: Text('Empty', style: TextStyle(color: C.inkSoft)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < _videos.length; i++)
                        _BlindItem(
                          creds: widget.creds,
                          path: _videos[i],
                          // 用路径 hash 定一个稳定的随机大小（34~58）
                          size: 34.0 +
                              (_videos[i].hashCode.abs() % 25).toDouble(),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// 盲盒单项：蓝色播放图标，大小随机，点了播放
class _BlindItem extends StatelessWidget {
  final SmbCreds creds;
  final String path;
  final double size;
  const _BlindItem({
    required this.creds,
    required this.path,
    required this.size,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => SmbClient.openExternal(creds, path),
      child: Icon(Icons.play_circle_outline, color: C.accent, size: size),
    );
  }
}