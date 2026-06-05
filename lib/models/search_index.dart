import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../smb/smb_client.dart';
import '../models/styles.dart';
import '../models/person.dart';
import '../models/person_meta.dart';

/// 人物记录（用于人物搜索）
class SearchPerson {
  final String name;
  final String path; // 相对 share 根的完整路径
  final bool isGroup; // 团体？点了走选成员
  final List<String> aliases; // 别名（也参与检索）
  const SearchPerson({
    required this.name,
    required this.path,
    required this.isGroup,
    this.aliases = const [],
  });
  Map<String, dynamic> toJson() => {
        'n': name,
        'p': path,
        'g': isGroup,
        if (aliases.isNotEmpty) 'a': aliases,
      };
  static SearchPerson fromJson(Map j) => SearchPerson(
        name: j['n'].toString(),
        path: j['p'].toString(),
        isGroup: j['g'] == true,
        aliases: (j['a'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// 作品记录（用于作品 / 时间搜索）
class SearchWork {
  final String fileName;
  final String personName;
  final String personPath;
  final String? date; // ISO: 2022 / 2022-01 / 2022-01-02
  const SearchWork({
    required this.fileName,
    required this.personName,
    required this.personPath,
    this.date,
  });
  Map<String, dynamic> toJson() => {
        'f': fileName,
        'p': personName,
        'pp': personPath,
        if (date != null && date!.isNotEmpty) 'd': date,
      };
  static SearchWork fromJson(Map j) => SearchWork(
        fileName: j['f'].toString(),
        personName: j['p'].toString(),
        personPath: j['pp'].toString(),
        date: j['d']?.toString(),
      );
}

/// 整个搜索索引
class SearchData {
  final List<SearchPerson> people;
  final List<SearchWork> works;
  const SearchData({this.people = const [], this.works = const []});
}

class SearchRepo {
  static Future<File> _file(String share) async {
    final dir = await getApplicationSupportDirectory();
    final safe = share.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/search_$safe.json');
  }

  /// 读取已存搜索索引；不存在返回 null
  static Future<SearchData?> read(String share) async {
    try {
      final f = await _file(share);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      final people = (j['people'] as List? ?? [])
          .whereType<Map>()
          .map((e) => SearchPerson.fromJson(e))
          .toList();
      final works = (j['works'] as List? ?? [])
          .whereType<Map>()
          .map((e) => SearchWork.fromJson(e))
          .toList();
      return SearchData(people: people, works: works);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String share, SearchData data) async {
    final f = await _file(share);
    final text = jsonEncode({
      'people': data.people.map((e) => e.toJson()).toList(),
      'works': data.works.map((e) => e.toJson()).toList(),
    });
    await f.writeAsString(text);
  }

  /// 清除所有搜索索引缓存（search_*.json）。不碰源文件。
  static Future<int> clearAll() async {
    final dir = await getApplicationSupportDirectory();
    var count = 0;
    try {
      await for (final ent in dir.list()) {
        final name = ent.path.split(Platform.pathSeparator).last;
        if (ent is File &&
            name.startsWith('search_') &&
            name.endsWith('.json')) {
          await ent.delete();
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// 全量重建搜索索引并写入。收录所有人物(含团体)与所有作品(不含 references)。
  static Future<SearchData> rebuild(
      SmbCreds c, String share, StylesConfig config) async {
    final people = <SearchPerson>[];
    final works = <SearchWork>[];

    for (final style in config.allRegistered) {
      final stylePath = '$share/$style';
      List<PersonNode> nodes;
      try {
        nodes = await PersonRepo.listPeople(c, stylePath);
      } catch (_) {
        continue;
      }
      for (final p in nodes) {
        bool group = false;
        try {
          group = await PersonRepo.isGroup(c, p.path);
        } catch (_) {}

        // 记录该节点本身（个人 或 团体）——带上别名
        people.add(SearchPerson(
          name: p.name,
          path: p.path,
          isGroup: group,
          aliases: await _aliasesOf(c, p.path),
        ));

        if (group) {
          // 团体：成员也各记为人物 + 收集成员作品
          List<PersonNode> members;
          try {
            members = await PersonRepo.listMembers(c, p.path);
          } catch (_) {
            members = [];
          }
          for (final m in members) {
            people.add(SearchPerson(
              name: m.name,
              path: m.path,
              isGroup: false,
              aliases: await _aliasesOf(c, m.path),
            ));
            await _collectWorks(c, m, works);
          }
        } else {
          // 个人：收集作品
          await _collectWorks(c, p, works);
        }
      }
    }

    final data = SearchData(people: people, works: works);
    await _write(share, data);
    return data;
  }

  // 读取某人物的别名（_person.json 的 aliases）
  static Future<List<String>> _aliasesOf(SmbCreds c, String personPath) async {
    try {
      final meta = await PersonMetaRepo.load(c, personPath);
      return meta.aliases;
    } catch (_) {
      return const [];
    }
  }

  // 收集某人物目录下所有实际视频作品（date 取自 person.json，不含 references）
  static Future<void> _collectWorks(
      SmbCreds c, PersonNode person, List<SearchWork> out) async {
    List<String> files;
    try {
      files = await PersonRepo.listWorks(c, person.path);
    } catch (_) {
      return;
    }
    PersonMeta meta;
    try {
      meta = await PersonMetaRepo.load(c, person.path);
    } catch (_) {
      meta = const PersonMeta();
    }
    for (final f in files) {
      final m = meta.items[f];
      out.add(SearchWork(
        fileName: f,
        personName: person.name,
        personPath: person.path,
        date: m?.date,
      ));
    }
  }
}

/// 把用户输入的时间归一化成 ISO 前缀：
/// "2022 1 3" / "2022.1.03" / "2022-1-3" -> "2022-01-03"
/// "2022 1" -> "2022-01"；"2022" -> "2022"；无数字 -> ''
String normalizeDateQuery(String input) {
  final nums = RegExp(r'\d+')
      .allMatches(input)
      .map((m) => m.group(0)!)
      .toList();
  if (nums.isEmpty) return '';
  final y = nums[0];
  final buf = StringBuffer(y);
  if (nums.length >= 2) {
    final m = int.tryParse(nums[1]);
    if (m != null) buf.write('-${m.toString().padLeft(2, '0')}');
  }
  if (nums.length >= 3) {
    final d = int.tryParse(nums[2]);
    if (d != null) buf.write('-${d.toString().padLeft(2, '0')}');
  }
  return buf.toString();
}

/// 时间匹配：归一化输入后，与作品 ISO date 做前缀匹配
bool matchDate(String? workDate, String query) {
  if (workDate == null || workDate.isEmpty) return false;
  final q = normalizeDateQuery(query);
  if (q.isEmpty) return false;
  return workDate.startsWith(q);
}