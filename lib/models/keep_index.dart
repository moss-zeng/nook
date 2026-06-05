import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../smb/smb_client.dart';
import '../models/styles.dart';
import '../models/person.dart';
import '../models/person_meta.dart';

/// 兜底用的很旧时间：老数据无 lovedAt 时按它排，自然沉到最后
const String _kFallbackLovedAt = '2000-01-01T00:00:00.000';

/// 索引里的一条作品记录
class IndexItem {
  final String fileName; // 作品文件名
  final String personName; // 人物名
  final String personPath; // 人物路径（相对 share 根，含 share）
  final String love; // 'preferred' / 'pinnacle'（passable 不入库）
  final String? date;
  final String lovedAt; // 收藏时间 ISO8601；无值兜底为很旧时间
  const IndexItem({
    required this.fileName,
    required this.personName,
    required this.personPath,
    required this.love,
    required this.lovedAt,
    this.date,
  });

  Map<String, dynamic> toJson() => {
        'f': fileName,
        'p': personName,
        'pp': personPath,
        'l': love,
        'la': lovedAt,
        if (date != null) 'd': date,
      };

  static IndexItem fromJson(Map j) => IndexItem(
        fileName: j['f']?.toString() ?? '',
        personName: j['p']?.toString() ?? '',
        personPath: j['pp']?.toString() ?? '',
        love: j['l']?.toString() ?? 'preferred',
        lovedAt: j['la']?.toString() ?? _kFallbackLovedAt,
        date: j['d']?.toString(),
      );
}

class IndexRepo {
  // 索引文件路径：私有目录/keep_<share>.json
  static Future<File> _file(String share) async {
    final dir = await getApplicationSupportDirectory();
    // share 名做简单清洗，避免非法文件名字符
    final safe = share.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/keep_$safe.json');
  }

  /// 读取已存索引；不存在返回 null
  static Future<List<IndexItem>?> read(String share) async {
    try {
      final f = await _file(share);
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      final list = jsonDecode(text);
      if (list is! List) return null;
      return list
          .whereType<Map>()
          .map((e) => IndexItem.fromJson(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String share, List<IndexItem> items) async {
    final f = await _file(share);
    final text = jsonEncode(items.map((e) => e.toJson()).toList());
    await f.writeAsString(text);
  }

  /// 清除所有 Keep 索引缓存（keep_*.json）。不碰磁盘源文件。
  static Future<int> clearAll() async {
    final dir = await getApplicationSupportDirectory();
    var count = 0;
    try {
      await for (final ent in dir.list()) {
        final name = ent.path.split(Platform.pathSeparator).last;
        if (ent is File &&
            name.startsWith('keep_') &&
            name.endsWith('.json')) {
          await ent.delete();
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// 全扫特定库，重建索引并写入本地。返回新索引。
  /// 只收集 love != passable 的作品。
  static Future<List<IndexItem>> rebuild(
      SmbCreds c, String share, StylesConfig config) async {
    final items = <IndexItem>[];
    // 遍历所有登记风格
    for (final style in config.allRegistered) {
      final stylePath = '$share/$style';
      List<PersonNode> people;
      try {
        people = await PersonRepo.listPeople(c, stylePath);
      } catch (_) {
        continue;
      }
      for (final p in people) {
        // 判定团体：团体则下钻成员，个人直接处理
        bool group = false;
        try {
          group = await PersonRepo.isGroup(c, p.path);
        } catch (_) {}
        final targets = <PersonNode>[];
        if (group) {
          try {
            targets.addAll(await PersonRepo.listMembers(c, p.path));
          } catch (_) {}
        } else {
          targets.add(p);
        }
        for (final person in targets) {
          await _collectPerson(c, person, items);
        }
      }
    }
    await _write(share, items);
    return items;
  }

  static Future<void> _collectPerson(
      SmbCreds c, PersonNode person, List<IndexItem> out) async {
    PersonMeta meta;
    try {
      meta = await PersonMetaRepo.load(c, person.path);
    } catch (_) {
      meta = const PersonMeta();
    }

    // 没有任何元数据，无需清理，直接返回
    if (meta.items.isEmpty && meta.references.isEmpty) return;

    // === 孤儿清理 ===
    // 1. 列出该人物目录实际视频文件；失败则跳过清理（不误删）
    List<String>? realFiles;
    try {
      realFiles = await PersonRepo.listWorks(c, person.path);
    } catch (_) {
      realFiles = null; // 列目录失败，本次不清理 items
    }

    var cleaned = meta;
    var changed = false;

    // 2. items 孤儿：文件名不在实际文件列表里 → 删
    if (realFiles != null) {
      final realSet = realFiles.toSet();
      final keptItems = <String, ItemMeta>{};
      meta.items.forEach((fileName, m) {
        if (realSet.contains(fileName)) {
          keptItems[fileName] = m;
        } else {
          changed = true; // 该 item 是孤儿，丢弃
        }
      });
      if (changed) {
        cleaned = PersonMeta(
          name: cleaned.name,
          aliases: cleaned.aliases,
          notes: cleaned.notes,
          items: keptItems,
          references: cleaned.references,
        );
      }
    }

    // 3. references 孤儿：逐条确认目标文件存在；查询失败则保留（不误删）
    if (cleaned.references.isNotEmpty) {
      final shareName = person.path.split('/').first;
      final keptRefs = <String>[];
      for (final ref in cleaned.references) {
        final full = '$shareName/$ref'; // 绝对路径（从风格起 → 拼 share）
        final lastSlash = full.lastIndexOf('/');
        if (lastSlash < 0) {
          keptRefs.add(ref); // 路径异常，保留
          continue;
        }
        final ownerDir = full.substring(0, lastSlash);
        final fileName = full.substring(lastSlash + 1);
        try {
          final entries = await SmbClient.list(c, ownerDir);
          final exists = entries.any((e) => !e.isDir && e.name == fileName);
          if (exists) {
            keptRefs.add(ref);
          } else {
            changed = true; // 确认不存在 → 删
          }
        } catch (_) {
          keptRefs.add(ref); // 查询失败 → 保留，绝不误删
        }
      }
      if (keptRefs.length != cleaned.references.length) {
        cleaned = PersonMeta(
          name: cleaned.name,
          aliases: cleaned.aliases,
          notes: cleaned.notes,
          items: cleaned.items,
          references: keptRefs,
        );
      }
    }

    // 4. 有删改 → 写回 person.json
    if (changed) {
      try {
        await PersonMetaRepo.save(c, person.path, cleaned);
      } catch (_) {
        // 写回失败不影响索引收集
      }
    }

    // 5. 用清理后的数据收集索引（只收 love != passable）
    cleaned.items.forEach((fileName, m) {
      if (m.love != Love.passable) {
        out.add(IndexItem(
          fileName: fileName,
          personName: person.name,
          personPath: person.path,
          love: loveToString(m.love)!,
          // 无 lovedAt 的老数据兜底为很旧时间，按收藏时间排序时沉到最后
          lovedAt: (m.lovedAt != null && m.lovedAt!.isNotEmpty)
              ? m.lovedAt!
              : _kFallbackLovedAt,
          date: m.date,
        ));
      }
    });
  }
}