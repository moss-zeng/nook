import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../widgets_love.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../models/styles.dart';
import '../models/person.dart';
import '../models/person_meta.dart';
import '../models/index.dart';
import 'person_page.dart';

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

  @override
  Widget build(BuildContext context) {
    final share = ref.watch(selectedShareProvider);
    final conn = ref.watch(connectionProvider);

    if (share == null || conn.creds == null) {
      return const Center(
        child: Text('Pick a share in Link',
            style: TextStyle(color: C.inkSoft, fontSize: 16)),
      );
    }

    if (_loadedShare != share && !_loading) {
      _loadedShare = share;
      _init(conn.creds!, share);
    }

    return Stack(
      children: [
        if (_loading || _rebuilding)
          const Center(child: CircularProgressIndicator(color: C.accent))
        else if (_notSpecific)
          const Center(
            child: Text('Not a media library',
                style: TextStyle(color: C.inkSoft)),
          )
        else
          _buildList(),
        // 右上角刷新按钮
        if (!_notSpecific)
          Positioned(
            top: 4,
            right: 16,
            child: _RefreshButton(
              spinning: _rebuilding,
              onTap: () => _rebuild(conn.creds!, share),
            ),
          ),
      ],
    );
  }

  // 首次：有索引直接读，无索引自动扫一次
  Future<void> _init(SmbCreds c, String share) async {
    setState(() => _loading = true);
    // 先确认是否特定库
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
    if (existing != null) {
      if (!mounted) return;
      setState(() {
        _items = existing;
        _loading = false;
        _notSpecific = false;
      });
    } else {
      setState(() => _loading = false);
      await _rebuild(c, share);
    }
  }

  Future<void> _rebuild(SmbCreds c, String share) async {
    final config = await StylesRepo.load(c, share);
    if (config == null) return;
    setState(() => _rebuilding = true);
    final items = await IndexRepo.rebuild(c, share, config);
    if (!mounted) return;
    setState(() {
      _items = items;
      _rebuilding = false;
      _notSpecific = false;
    });
  }

  Widget _buildList() {
    final items = _items ?? [];
    final pinnacle = items.where((e) => e.love == 'pinnacle').toList()
      ..shuffle(Random());
    final preferred = items.where((e) => e.love == 'preferred').toList()
      ..shuffle(Random());

    if (pinnacle.isEmpty && preferred.isEmpty) {
      return const Center(
        child: Text('Nothing kept yet',
            style: TextStyle(color: C.inkSoft)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 100),
      children: [
        for (final it in pinnacle) _row(it),
        if (pinnacle.isNotEmpty && preferred.isNotEmpty)
          const SizedBox(height: 24),
        for (final it in preferred) _row(it),
      ],
    );
  }

  Widget _row(IndexItem it) {
    final creds = ref.read(connectionProvider).creds!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // love 小图标
          LoveBadge(
            love: it.love == 'pinnacle' ? Love.pinnacle : Love.preferred,
            size: 18,
          ),
          const SizedBox(width: 10),
          // 左 70% 作品名（点击跳作品）
          Expanded(
            flex: 7,
            child: GestureDetector(
              onTap: () => _openWork(creds, it),
              child: Text(
                _stripExt(it.fileName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: C.ink, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 右 30% 人物名（点击跳人物）
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _openPerson(creds, it),
              child: Text(
                it.personName,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.accent, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openWork(SmbCreds c, IndexItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(
        creds: c,
        person: PersonNode(name: it.personName, path: it.personPath),
        initialWork: it.fileName,
      ),
    ));
  }

  void _openPerson(SmbCreds c, IndexItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(
        creds: c,
        person: PersonNode(name: it.personName, path: it.personPath),
      ),
    ));
  }

  String _stripExt(String f) {
    final i = f.lastIndexOf('.');
    return i > 0 ? f.substring(0, i) : f;
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
        child: const Icon(Icons.refresh, color: C.inkSoft, size: 24),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Settings',
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w600, color: C.inkSoft)),
    );
  }
}
