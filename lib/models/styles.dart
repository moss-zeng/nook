import 'dart:convert';
import '../smb/smb_client.dart';

/// 一个风格组：字段名（不展示）+ 该组下的风格名列表
class StyleGroup {
  final String field; // styles1 / styles2 ...
  final List<String> styles;
  StyleGroup(this.field, this.styles);
}

/// _styles.json 的解析结果
class StylesConfig {
  final List<StyleGroup> groups;
  StylesConfig(this.groups);

  /// 所有已登记的风格名（跨组）
  Set<String> get allRegistered => groups.expand((g) => g.styles).toSet();
}

class StylesRepo {
  /// 读取并解析某 share 根目录的 _styles.json。
  /// 读不到或解析失败 → 返回 null（调用方据此判定普通模式）。
  static Future<StylesConfig?> load(SmbCreds c, String share) async {
    try {
      final text = await SmbClient.readFile(c, '$share/_styles.json');
      if (text == null || text.trim().isEmpty) return null;
      final map = jsonDecode(text);
      if (map is! Map) return null;
      final groups = <StyleGroup>[];
      map.forEach((k, v) {
        if (v is List) {
          groups.add(
              StyleGroup(k.toString(), v.map((e) => e.toString()).toList()));
        }
      });
      if (groups.isEmpty) return null;
      return StylesConfig(groups);
    } catch (_) {
      return null;
    }
  }

  /// 写回 _styles.json，保留字段顺序，规整缩进
  static Future<void> save(
      SmbCreds c, String share, StylesConfig config) async {
    final map = <String, dynamic>{};
    for (final g in config.groups) {
      map[g.field] = g.styles;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await SmbClient.writeFile(c, '$share/_styles.json', encoder.convert(map));
  }
}
