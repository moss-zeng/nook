import 'dart:convert';
import '../smb/smb_client.dart';

enum Love { passable, preferred, pinnacle }

Love loveFromString(String? s) {
  switch (s) {
    case 'preferred':
      return Love.preferred;
    case 'pinnacle':
      return Love.pinnacle;
    default:
      return Love.passable;
  }
}

String? loveToString(Love l) {
  switch (l) {
    case Love.preferred:
      return 'preferred';
    case Love.pinnacle:
      return 'pinnacle';
    case Love.passable:
      return null; // 默认不写
  }
}

/// 单个作品的元数据
class ItemMeta {
  final String? date;
  final String? description;
  final Love love;
  final String? lovedAt; // 最近一次变成收藏态(preferred/pinnacle)的时间，ISO8601
  const ItemMeta(
      {this.date, this.description, this.love = Love.passable, this.lovedAt});

  ItemMeta copyWith(
          {String? date, String? description, Love? love, String? lovedAt}) =>
      ItemMeta(
        date: date ?? this.date,
        description: description ?? this.description,
        love: love ?? this.love,
        lovedAt: lovedAt ?? this.lovedAt,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (date != null && date!.isNotEmpty) m['date'] = date;
    if (description != null && description!.isNotEmpty) {
      m['description'] = description;
    }
    final l = loveToString(love);
    if (l != null) m['love'] = l;
    if (lovedAt != null && lovedAt!.isNotEmpty) m['lovedAt'] = lovedAt;
    return m;
  }

  bool get isEmpty =>
      (date == null || date!.isEmpty) &&
      (description == null || description!.isEmpty) &&
      love == Love.passable;
}

/// _person.json 的完整内容
class PersonMeta {
  final String? name;
  final List<String> aliases;
  final String? notes;
  final Map<String, ItemMeta> items; // key=作品文件名
  final List<String> references; // 绝对路径（从风格起）

  const PersonMeta({
    this.name,
    this.aliases = const [],
    this.notes,
    this.items = const {},
    this.references = const [],
  });

  ItemMeta itemFor(String fileName) => items[fileName] ?? const ItemMeta();

  PersonMeta withItem(String fileName, ItemMeta meta) {
    final m = Map<String, ItemMeta>.from(items);
    if (meta.isEmpty) {
      m.remove(fileName); // 空元数据不保留该 key
    } else {
      m[fileName] = meta;
    }
    return PersonMeta(
      name: name,
      aliases: aliases,
      notes: notes,
      items: m,
      references: references,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null && name!.isNotEmpty) m['name'] = name;
    if (aliases.isNotEmpty) m['aliases'] = aliases;
    if (notes != null && notes!.isNotEmpty) m['notes'] = notes;
    if (items.isNotEmpty) {
      final im = <String, dynamic>{};
      items.forEach((k, v) {
        final j = v.toJson();
        if (j.isNotEmpty) im[k] = j;
      });
      if (im.isNotEmpty) m['items'] = im;
    }
    if (references.isNotEmpty) m['references'] = references;
    return m;
  }
}

class PersonMetaRepo {
  /// 读取某人物的 _person.json，不存在/出错返回空 PersonMeta
  static Future<PersonMeta> load(SmbCreds c, String personPath) async {
    try {
      final text = await SmbClient.readFile(c, '$personPath/_person.json');
      if (text == null || text.trim().isEmpty) return const PersonMeta();
      final map = jsonDecode(text);
      if (map is! Map) return const PersonMeta();

      final items = <String, ItemMeta>{};
      final rawItems = map['items'];
      if (rawItems is Map) {
        rawItems.forEach((k, v) {
          if (v is Map) {
            items[k.toString()] = ItemMeta(
              date: v['date']?.toString(),
              description: v['description']?.toString(),
              love: loveFromString(v['love']?.toString()),
              lovedAt: v['lovedAt']?.toString(),
            );
          }
        });
      }
      final aliases = <String>[];
      if (map['aliases'] is List) {
        for (final a in (map['aliases'] as List)) {
          aliases.add(a.toString());
        }
      }
      final refs = <String>[];
      if (map['references'] is List) {
        for (final r in (map['references'] as List)) {
          refs.add(r.toString());
        }
      }
      return PersonMeta(
        name: map['name']?.toString(),
        aliases: aliases,
        notes: map['notes']?.toString(),
        items: items,
        references: refs,
      );
    } catch (_) {
      return const PersonMeta();
    }
  }

  /// 写回 person.json
  static Future<void> save(
      SmbCreds c, String personPath, PersonMeta meta) async {
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(meta.toJson());
    await SmbClient.writeFile(c, '$personPath/_person.json', json);
  }
}