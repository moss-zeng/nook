import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../theme.dart';
import '../smb/smb_client.dart';
import '../models/person.dart';
import '../widgets.dart';
import 'person_page.dart';

/// 第二层：某风格下的人物 / 团体瀑布流
class PeoplePage extends StatefulWidget {
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
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  List<PersonNode> _people = [];
  bool _loading = true;
  bool _busy = false; // 防止重复点击时并发判定

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PersonRepo.listPeople(widget.creds, widget.stylePath);
    if (!mounted) return;
    setState(() {
      _people = list;
      _loading = false;
    });
  }

  Future<void> _onTapPerson(PersonNode p) async {
    if (_busy) return;
    _busy = true;
    try {
      final group = await PersonRepo.isGroup(widget.creds, p.path);
      if (!mounted) return;
      if (!group) {
        _openPerson(p);
        return;
      }
      final members = await PersonRepo.listMembers(widget.creds, p.path);
      if (!mounted) return;
      final picked = await showDialog<PersonNode>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.35),
        builder: (_) => _MemberPicker(
          creds: widget.creds,
          groupName: p.name,
          members: members,
        ),
      );
      if (picked != null) _openPerson(picked);
    } finally {
      _busy = false;
    }
  }

  void _openPerson(PersonNode p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(creds: widget.creds, person: p),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
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
                        color: C.ink, size: 20),
                  ),
                  Text('#${widget.styleName}',
                      style: const TextStyle(
                          color: C.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: C.accent))
                  : _people.isEmpty
                      ? const Center(
                          child: Text('Empty',
                              style: TextStyle(color: C.inkSoft)))
                      : MasonryGridView.count(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          itemCount: _people.length,
                          itemBuilder: (_, i) {
                            final p = _people[i];
                            return _PersonTile(
                              creds: widget.creds,
                              person: p,
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

/// 瀑布流单元：封面原始比例；无封面则白底蓝字名
class _PersonTile extends StatelessWidget {
  final SmbCreds creds;
  final PersonNode person;
  final VoidCallback onTap;
  const _PersonTile({
    required this.creds,
    required this.person,
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
          candidates: ['${person.path}/_cover.jpg'],
          fallbackName: person.name,
          aspectRatioFallback: 0.8,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// 团体成员选择浮层
class _MemberPicker extends StatelessWidget {
  final SmbCreds creds;
  final String groupName;
  final List<PersonNode> members;
  const _MemberPicker({
    required this.creds,
    required this.groupName,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: C.surface,
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
                          color: C.ink)),
                  const SizedBox(height: 16),
                  Flexible(
                    child: members.isEmpty
                        ? const Text('No members',
                            style: TextStyle(color: C.inkSoft))
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
                              return GestureDetector(
                                onTap: () => Navigator.pop(context, m),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: CoverImage(
                                          creds: creds,
                                          candidates: [
                                            '${m.path}/_cover.jpg'
                                          ],
                                          fallbackName: m.name,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(m.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: C.ink, fontSize: 12)),
                                  ],
                                ),
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
