import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme.dart';
import '../widgets.dart';
import '../state/connection.dart';
import '../smb/smb_client.dart';
import '../models/person.dart';
import '../models/search_index.dart';
import '../widgets_date.dart';
import 'person_page.dart';

enum SearchTab { people, works, time }

class SearchPage extends StatefulWidget {
  final SmbCreds creds;
  final String share;
  const SearchPage({super.key, required this.creds, required this.share});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  SearchTab _tab = SearchTab.people;
  SearchData? _data;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      setState(() => _query = _ctrl.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await SearchRepo.read(widget.share);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  // ===== 结果过滤 =====
  List<SearchPerson> get _peopleResults {
    final d = _data;
    if (d == null || _query.isEmpty) return const [];
    final q = _query.toLowerCase();
    return d.people
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.aliases.any((a) => a.toLowerCase().contains(q)))
        .toList();
  }

  List<SearchWork> get _workResults {
    final d = _data;
    if (d == null || _query.isEmpty) return const [];
    final q = _query.toLowerCase();
    return d.works
        .where((w) => w.fileName.toLowerCase().contains(q))
        .toList();
  }

  List<SearchWork> get _timeResults {
    final d = _data;
    if (d == null || _query.isEmpty) return const [];
    return d.works.where((w) => matchDate(w.date, _query)).toList();
  }

  // ===== 跳转 =====
  void _openPerson(SearchPerson p) async {
    if (p.isGroup) {
      // 团体：弹成员选择
      List<PersonNode> members;
      try {
        members = await PersonRepo.listMembers(
            widget.creds, p.path);
      } catch (_) {
        members = [];
      }
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
      if (picked != null && mounted) {
        _pushPerson(PersonNode(name: picked.name, path: picked.path));
      }
    } else {
      _pushPerson(PersonNode(name: p.name, path: p.path));
    }
  }

  void _pushPerson(PersonNode node, {String? initialWork}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PersonPage(
        creds: widget.creds,
        person: node,
        spec: PersonColorSpec.person(node.name),
        initialWork: initialWork,
      ),
    ));
  }

  void _openWork(SearchWork w) {
    _pushPerson(
      PersonNode(name: w.personName, path: w.personPath),
      initialWork: w.fileName,
    );
  }

  String _stripExt(String f) {
    final i = f.lastIndexOf('.');
    return i > 0 ? f.substring(0, i) : f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: View_C.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏：返回 + 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: View_C.ink, size: 20),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      style: const TextStyle(color: View_C.ink, fontSize: 15),
                      cursorColor: View_C.barBg,
                      decoration: InputDecoration(
                        hintText: _hintText(),
                        hintStyle: const TextStyle(color: View_C.inkSoft),
                        filled: true,
                        fillColor: View_C.surface,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close,
                                    size: 18, color: View_C.inkSoft),
                                onPressed: () => _ctrl.clear(),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 分段控件
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SegTabs(
                current: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
            const Divider(color: View_C.line, height: 1),
            // 结果
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  String _hintText() => switch (_tab) {
        SearchTab.people => 'Search people…',
        SearchTab.works => 'Search works…',
        SearchTab.time => 'e.g. 2022 / 2022-06 / 2022 6 21',
      };

  Widget _buildResults() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: View_C.barBg));
    }
    if (_data == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No search index yet.\nBuild it in Settings → Rebuild search index.',
            textAlign: TextAlign.center,
            style: TextStyle(color: View_C.inkSoft, height: 1.5),
          ),
        ),
      );
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(
          switch (_tab) {
            SearchTab.people => 'Type to search people',
            SearchTab.works => 'Type to search works',
            SearchTab.time => 'Type a date to search',
          },
          style: const TextStyle(color: View_C.inkSoft),
        ),
      );
    }

    if (_tab == SearchTab.people) {
      final res = _peopleResults;
      if (res.isEmpty) return _empty();
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        itemCount: res.length,
        separatorBuilder: (_, __) => const Divider(color: View_C.line, height: 1),
        itemBuilder: (_, i) {
          final p = res[i];
          return ListTile(
            leading: Icon(
              p.isGroup ? Symbols.groups : Symbols.person,
              color: View_C.barBg,
            ),
            title: Text(p.name, style: const TextStyle(color: View_C.ink)),
            subtitle: p.isGroup
                ? const Text('Group', style: TextStyle(color: View_C.inkSoft))
                : null,
            onTap: () => _openPerson(p),
          );
        },
      );
    }

    // works / time
    final res = _tab == SearchTab.works ? _workResults : _timeResults;
    if (res.isEmpty) return _empty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: res.length,
      separatorBuilder: (_, __) => const Divider(color: View_C.line, height: 1),
      itemBuilder: (_, i) {
        final w = res[i];
        return ListTile(
          leading: const Icon(Symbols.movie, color: View_C.barBg),
          title: Text(_stripExt(w.fileName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: View_C.ink)),
          subtitle: Text(
            w.date != null && w.date!.isNotEmpty
                ? '${w.personName}  ·  ${formatDate(w.date)}'
                : w.personName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: View_C.inkSoft, fontSize: 12),
          ),
          onTap: () => _openWork(w),
        );
      },
    );
  }

  Widget _empty() => const Center(
        child: Text('No results', style: TextStyle(color: View_C.inkSoft)),
      );
}

// 分段控件：人物 / 作品 / 时间
class _SegTabs extends StatelessWidget {
  final SearchTab current;
  final ValueChanged<SearchTab> onChanged;
  const _SegTabs({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: View_C.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _seg(SearchTab.people, Symbols.person),
          _seg(SearchTab.works, Symbols.movie),
          _seg(SearchTab.time, Symbols.calendar_month),
        ],
      ),
    );
  }

  Widget _seg(SearchTab t, IconData icon) {
    final on = t == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? View_C.barBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 22, color: on ? Colors.white : View_C.inkSoft),
        ),
      ),
    );
  }
}

// 团体成员选择（与 people_page 同款简化版）
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
          color: View_C.surface,
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
                                            color: View_C.ink, fontSize: 12)),
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