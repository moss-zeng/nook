import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../state/connection.dart';
import '../models/keep_index.dart';
import '../models/cover_index.dart';
import '../widgets.dart';
import '../models/styles.dart';
import '../models/search_index.dart';
import '../smb/smb_client.dart';

const _githubUrl = 'https://github.com/moss-zeng/nook';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _zh = false; // 语言：false=EN, true=中（仅本页）

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        // 顶部语言切换
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_zh ? '设置' : 'Settings',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: C.ink)),
            _LangToggle(
              zh: _zh,
              onChanged: (v) => setState(() => _zh = v),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 简介
        Text(
          _zh ? _introZh : _introEn,
          style: const TextStyle(color: C.inkSoft, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 24),

        // How it works
        _sectionTitle(_zh ? '工作方式' : 'How it works'),
        const SizedBox(height: 14),

        // ① 普通库 vs 风格库
        _blockTitle(_zh ? '普通库与风格库' : 'Plain vs style library'),
        const SizedBox(height: 8),
        _codeBlock(_tree1),
        const SizedBox(height: 8),
        _blockText(_zh ? _desc1Zh : _desc1En),
        const SizedBox(height: 20),

        // ② 风格库结构
        _blockTitle(_zh ? '风格库结构' : 'Style library structure'),
        const SizedBox(height: 8),
        _codeBlock(_tree2),
        const SizedBox(height: 8),
        _blockText(_zh ? _desc2Zh : _desc2En),
        const SizedBox(height: 20),

        // ③ 特殊文件夹
        _blockTitle(_zh ? '特殊文件夹' : 'Special folders'),
        const SizedBox(height: 8),
        _codeBlock(_tree3),
        const SizedBox(height: 8),
        _blockText(_zh ? _desc3Zh : _desc3En),

        const SizedBox(height: 24),

        // About
        _sectionTitle(_zh ? '关于' : 'About'),
        const SizedBox(height: 10),
        _card(
          child: Row(
            children: [
              Text(_zh ? '作者：' : 'Author: ',
                  style: const TextStyle(color: C.inkSoft, fontSize: 13)),
              const Text('Moss',
                  style: TextStyle(
                      color: C.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _openGithub,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, color: C.accent, size: 16),
                    const SizedBox(width: 6),
                    const Text('GitHub',
                        style: TextStyle(
                            color: C.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Actions
        _sectionTitle(_zh ? '操作' : 'Actions'),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.link_off,
          label: _zh ? '断开连接' : 'Disconnect',
          desc: _zh
              ? '清除连接信息'
              : 'Clear Connection Information',
          onTap: _disconnect,
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.manage_search,
          label: _zh ? '重建索引' : 'Rebuild Index',
          desc: _zh
              ? '全量扫描当前库'
              : 'Full Scan of Current Library',
          onTap: _rebuildAll,
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.cached,
          label: _zh ? '清除索引缓存' : 'Clear Index Cache',
          desc: _zh
              ? '删除全部本地索引缓存'
              : 'Delete All Local Index Cache',
          onTap: _clearAll,
        ),
        const SizedBox(height: 10),
        _switchTile(
          icon: Icons.palette_outlined,
          label: _zh ? '随机配色' : 'Random Colors',
          desc: _zh
              ? '让展示区的颜色随机'
              : 'Randomize Display Area Colors',
          value: ref.watch(personColorModeProvider),
          onChanged: (v) =>
              ref.read(personColorModeProvider.notifier).setRandom(v),
        ),
      ],
    );
  }

  // 大区标题（工作方式/关于/操作）：醒目大黑字
  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: C.ink, fontSize: 16, fontWeight: FontWeight.w700));

  // 子块标题（普通库与风格库等）：次级小灰字
  Widget _blockTitle(String t) => Text(t,
      style: const TextStyle(
          color: C.inkSoft, fontSize: 13, fontWeight: FontWeight.w700));

  // 说明文字：每段独立、段间留白，避免堆叠拥挤
  Widget _blockText(List<String> paras) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < paras.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Text(paras[i],
                style: const TextStyle(
                    color: C.inkSoft, fontSize: 12.5, height: 1.5)),
          ],
        ],
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.line),
        ),
        child: child,
      );

  Widget _codeBlock(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.barBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(
                color: C.ink, fontSize: 11.5, height: 1.5, fontFamily: 'monospace')),
      );

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
  }) =>
      Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                Icon(icon, color: C.accent, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: C.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(desc,
                          style: const TextStyle(
                              color: C.inkSoft, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: C.inkSoft, size: 20),
              ],
            ),
          ),
        ),
      );

  Future<void> _openGithub() async {
    final uri = Uri.parse(_githubUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    final ok = await _confirm(
      _zh ? '断开连接？' : 'Disconnect?',
      _zh
          ? '将清除已保存的连接信息，下次需要重新输入。'
          : 'This clears saved connection info. You will need to enter it again.',
    );
    if (ok != true) return;
    await ref.read(connectionProvider.notifier).disconnect();
    ref.read(selectedShareProvider.notifier).set(null);
  }

  // 重建全部索引：搜索 + 收藏(keep) + 封面比例(cover)
  Future<void> _rebuildAll() async {
    final creds = ref.read(connectionProvider).creds;
    final share = ref.read(selectedShareProvider);
    if (creds == null || share == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(
                _zh ? '请先连接并打开一个库' : 'Connect and open a library first')));
      return;
    }
    final ok = await _confirm(
      _zh ? '重建索引？' : 'Rebuild index?',
      _zh
          ? '将全量扫描当前库（搜索 / 收藏 / 封面），可能需要一些时间。'
          : 'Full scan of the current library (search / keep / covers). This may take a while.',
    );
    if (ok != true) return;
    if (!mounted) return;

    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: C.accent)),
    );

    final sw = Stopwatch()..start();
    String msg;
    try {
      final cfg = await StylesRepo.load(creds, share);
      if (cfg == null) {
        msg = _zh ? '当前库不是风格库' : 'Current library is not a style library';
      } else {
        final data = await SearchRepo.rebuild(creds, share, cfg);
        await IndexRepo.rebuild(creds, share, cfg);
        final covers = await CoverIndexRepo.rebuild(creds, share, cfg);
        CoverCache.clearAll(); // 新功能代码，完整保留
        sw.stop();
        final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
        msg = _zh
            ? '完成：${data.people.length} 人物 / ${data.works.length} 作品 / ${covers.length} 封面，用时 ${secs}s'
            : 'Done: ${data.people.length} people / ${data.works.length} works / ${covers.length} covers in ${secs}s';
      }
    } catch (e) {
      msg = _zh ? '失败：$e' : 'Failed: $e';
    }

    closeDialog();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // 清除全部本地索引缓存：keep + search + cover
  Future<void> _clearAll() async {
    final ok = await _confirm(
      _zh ? '清除索引缓存？' : 'Clear Index Cache?',
      _zh
          ? '只删除本地索引缓存，不影响磁盘上的任何文件。'
          : 'Deletes local index cache only. No files on disk are touched.',
    );
    if (ok != true) return;
    var n = 0;
    n += await IndexRepo.clearAll();
    n += await SearchRepo.clearAll();
    n += await CoverIndexRepo.clearAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(_zh ? '已清除 $n 个缓存' : 'Cleared $n cache file(s)')));
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(_zh ? '取消' : 'Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(_zh ? '确认' : 'OK')),
        ],
      ),
    );
  }
}

Widget _switchTile({
    required IconData icon,
    required String label,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: Row(
          children: [
            Icon(icon, color: C.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: C.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(color: C.inkSoft, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: C.accent,
            ),
          ],
        ),
      );

class _LangToggle extends StatelessWidget {
  final bool zh;
  final ValueChanged<bool> onChanged;
  const _LangToggle({required this.zh, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.barBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _seg('EN', !zh, () => onChanged(false)),
          _seg('中', zh, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(String t, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: on ? C.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(t,
              style: TextStyle(
                  color: on ? Colors.white : C.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

// ===== 文案 =====
const _introEn =
    'A local media manager for personal collectors on Android — browse and organize files on your PC or NAS over SMB.';
const _introZh =
    '面向个人收藏者的本地媒体管理器 —— 通过 SMB 浏览、整理电脑或 NAS 上的文件。';

const _tree1 = '''Share/
├── _styles.json
└── ...''';
const _desc1En = [
  'nook accesses shared folders on your PC or NAS over SMB.',
  'A share whose root contains _styles.json is a "style library" — nook organizes it by your defined structure. Without it, the share is a "plain library", browsed as ordinary files.',
  'The mode is detected automatically when you open a share.',
];
const _desc1Zh = [
  'nook 通过 SMB 访问电脑或 NAS 上的共享文件夹。',
  '根目录下有 _styles.json 的是「风格库」，nook 会按收藏者定义的结构组织展示；没有则是「普通库」，只能正常浏览文件夹和文件。',
  '打开 share 时自动判断，无需手动切换。',
];

const _tree2 = '''Share/
└── Person/
    ├── _cover.jpg
    └── work.mp4
└── Group/
    ├── _cover.jpg
    ├── Member1/
    │   └── collab.mp4
    └── Member2/
        └── _person.json''';
const _desc2En = [
  'A style library is organized in three layers: style → person / group → work.',
  'The top level are styles (folders registered in _styles.json). Below a style are individual subjects: a folder with no subfolders (only files) is a person; a folder containing subfolders is a group, whose subfolders are its members.',
  'A collaborative work is stored under just one member; others reference it via references, and its info belongs to the member who stores it.',
];
const _desc2Zh = [
  '风格库按「风格 → 人物 / 团体 → 作品」三层组织。',
  '顶层是风格，风格之下是一个个对象。一个文件夹不含子文件夹时视为人物；含子文件夹时视为团体，其子文件夹是成员。',
  '团体合作的作品只实际存放在某一位成员名下，其他成员通过 references 引用同一件作品，信息归属于存放它的那位成员。',
];

const _tree3 = '''Share/
├── _styles.json
├── _inbox/
├── _blindbox/
└── Style/
    └── Person/
        ├── _cover.jpg
        ├── _person.json
        ├── .covers/
        └── .gallery/''';
const _desc3En = [
  'Folders starting with _ or . are not shown as style content.',
  '_styles.json is the style registry; _inbox/ is a staging area for unsorted items; _blindbox/ is a flat pile for things you don\'t want to sort or can\'t bear to delete.',
  'Inside each person folder: _cover.jpg is the cover; _person.json holds favorites / notes / dates; .covers/ holds work covers; .gallery/ is an image gallery.',
  'All are optional, created on demand, and stored as plain files alongside your collection, all actions only moves and renames — it never deletes anything.',
];
const _desc3Zh = [
  '以 _ 或 . 开头的文件夹不会被当作风格内容展示。',
  '_styles.json 是风格登记表；_inbox/ 是暂存区，临时堆放尚未归类的内容；_blindbox/ 是盲盒，内容平铺、随手翻看，适合放一时不想整理或不舍得删的东西。',
  '每个人物文件夹下：_cover.jpg 是封面；_person.json 存喜爱 / 简介 / 日期；.covers/ 存作品封面；.gallery/ 是图片库。',
  '这些都是可选的、按需生成，直接以文件形式和收藏存在一起，所有操作只移动和重命名，绝不删除任何文件。',
];