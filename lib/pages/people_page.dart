import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../theme.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../models/person.dart';
import '../models/cover_index.dart';
import '../widgets.dart';
import 'person_page.dart';

/// 第二层：某风格下的人物 / 团体瀑布流
class PeoplePage extends ConsumerStatefulWidget {
  final SmbCreds creds;
  final String stylePath;
  final String styleName;
  const PeoplePage({
    super.key,
    required this.creds,
    required this.stylePath,
    required this.styleName,
  });
  @override
  ConsumerState<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends ConsumerState<PeoplePage> {
  List<PersonNode> _people = [];
  bool _loading = true;
  bool _busy = false; // 防止重复点击时并发判定
  Map<String, double> _coverAr = {}; // 封面路径→宽高比（cover_index，瀑布流不跳）

  @override
  void initState() {
    super.initState();
    // 第二层（人物/团体列表）：搜索按钮用默认色
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(viewAccentProvider.notifier).set(null);
    });
    _load();
  }

  Future<void> _load() async {
    final share = ref.read(selectedShareProvider);
    final list = await PersonRepo.listPeople(widget.creds, widget.stylePath);
    final coverAr = share != null
        ? await CoverIndexRepo.read(share)
        : <String, double>{};
    if (!mounted) return;
    setState(() {
      _people = list;
      _coverAr = coverAr;
      _loading = false;
    });
  }

  Future<void> _onTapPerson(PersonNode p) async {
    if (_busy) return;
    _busy = true;
    try {
      final share = ref.read(selectedShareProvider);
      final group = await PersonRepo.isGroup(widget.creds, p.path);
      if (!mounted) return;
      if (!group) {
        // 单人：根色号按人名（活值）
        _openPerson(p, PersonColorSpec.person(p.name));
        return;
      }
      final members = await PersonRepo.listMembers(widget.creds, p.path);
      if (!mounted) return;
      // 团体根色号（活值）；弹面板期间搜索按钮底色 = 团体色
      final groupIdx = personColorIdx(ref, p.name, share);
      ref.read(viewAccentProvider.notifier).set(groupIdx);
      final picked = await showDialog<int>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.35),
        builder: (_) => _MemberPicker(
          creds: widget.creds,
          groupName: p.name,
          members: members,
          groupColorIdx: groupIdx,
        ),
      );
      if (!mounted) return;
      if (picked != null) {
        // 团员：根色号 = 团体名 + 顺位（活值）
        final m = members[picked];
        _openPerson(m, PersonColorSpec.member(p.name, picked));
      } else {
        ref.read(viewAccentProvider.notifier).set(null);
      }
    } finally {
      _busy = false;
    }
  }

  void _openPerson(PersonNode p, PersonColorSpec spec) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) =>
              PersonPage(creds: widget.creds, person: p, spec: spec),
        ))
        .then((_) {
      // 返回到人物/团体列表：搜索按钮恢复默认色
      if (mounted) ref.read(viewAccentProvider.notifier).set(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: View_C.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: View_C.barBg, size: 20),
                  ),
                  Text('#${widget.styleName}',
                      style: const TextStyle(
                          color: View_C.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: View_C.accent))
                  : _people.isEmpty
                      ? const Center(
                          child: Text('Empty',
                              style: TextStyle(color: View_C.inkSoft)))
                      : MasonryGridView.count(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          itemCount: _people.length,
                          itemBuilder: (_, i) {
                            final p = _people[i];
                            // 从候选封面路径里找 cover_index 已知比例
                            double? ar;
                            for (final cand in coverCandidates(p.path)) {
                              final v = _coverAr[cand];
                              if (v != null) {
                                ar = v;
                                break;
                              }
                            }
                            return _PersonTile(
                              creds: widget.creds,
                              person: p,
                              colorIdx: personColorIdx(
                                  ref, p.name, ref.watch(selectedShareProvider)),
                              knownAspectRatio: ar,
                              onTap: () => _onTapPerson(p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 瀑布流单元：封面原始比例；无封面则 Style_C 随机色块 + 名字
class _PersonTile extends StatelessWidget {
  final SmbCreds creds;
  final PersonNode person;
  final int colorIdx;
  final double? knownAspectRatio;
  final VoidCallback onTap;
  const _PersonTile({
    required this.creds,
    required this.person,
    required this.colorIdx,
    required this.knownAspectRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CoverImage(
          creds: creds,
          candidates: coverCandidates(person.path),
          fallbackName: person.name,
          fallbackColorIdx: colorIdx,
          aspectRatioFallback: 0.8,
          knownAspectRatio: knownAspectRatio,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// 团体成员选择浮层。返回被选成员在 members 中的下标。
class _MemberPicker extends StatelessWidget {
  final SmbCreds creds;
  final String groupName;
  final List<PersonNode> members;
  final int groupColorIdx;
  const _MemberPicker({
    required this.creds,
    required this.groupName,
    required this.members,
    required this.groupColorIdx,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 面板底 = surface 与团体色混合（偏团体色但保证文字对比度）
    final panelBg = Color.alphaBlend(
        Style_C.bg(groupColorIdx).withOpacity(0.5), View_C.surface);
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
                  Text(groupName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: View_C.ink)),
                  const SizedBox(height: 16),
                  Flexible(
                    child: members.isEmpty
                        ? const Text('No members',
                            style: TextStyle(color: View_C.inkSoft))
                        : GridView.builder(
                            shrinkWrap: true,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: members.length,
                            itemBuilder: (_, i) {
                              final m = members[i];
                              // 成员顺位色：团体色号 +1、+2……
                              final mIdx = Style_C.norm(groupColorIdx + 1 + i);
                              return _MemberCard(
                                creds: creds,
                                member: m,
                                colorIdx: mIdx,
                                onTap: () => Navigator.pop(context, i),
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

/// 成员卡：名字分流——有封面显示下方小字名（随机色），无封面靠色块上的名、不显小字
class _MemberCard extends StatefulWidget {
  final SmbCreds creds;
  final PersonNode member;
  final int colorIdx;
  final VoidCallback onTap;
  const _MemberCard({
    required this.creds,
    required this.member,
    required this.colorIdx,
    required this.onTap,
  });
  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  bool? _hasCover; // null=未解析；true/false=是否有封面

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CoverImage(
                creds: widget.creds,
                candidates: coverCandidates(widget.member.path),
                fallbackName: widget.member.name,
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
          // 仅"有封面"时显示下方小字名（随机色）；无封面靠色块上的名
          if (_hasCover == true) ...[
            const SizedBox(height: 6),
            Text(widget.member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Style_C.ink(widget.colorIdx), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}