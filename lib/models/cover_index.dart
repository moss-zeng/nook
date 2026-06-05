import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import '../smb/smb_client.dart';
import '../models/styles.dart';
import '../models/person.dart';

/// 封面尺寸索引：封面完整路径 → 宽高比(width/height)。
/// 人物封面 key 形如 "人物路径/_cover.jpg"；
/// 作品封面 key 形如 "人物路径/.covers/作品名.jpg"。
/// 列表渲染前查它拿到真实比例，占位即用，加载前后高度一致 → 瀑布流不跳。
class CoverIndexRepo {
  static const List<String> _coverExts = [
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'
  ];

  static Future<File> _file(String share) async {
    final dir = await getApplicationSupportDirectory();
    final safe = share.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/cover_$safe.json');
  }

  /// 读取已存尺寸字典；不存在返回空 map
  static Future<Map<String, double>> read(String share) async {
    try {
      final f = await _file(share);
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return {};
      final out = <String, double>{};
      j.forEach((k, v) {
        final d = (v is num) ? v.toDouble() : double.tryParse('$v');
        if (d != null && d > 0) out[k.toString()] = d;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(String share, Map<String, double> map) async {
    final f = await _file(share);
    await f.writeAsString(jsonEncode(map));
  }

  /// 清除所有封面尺寸索引缓存（cover_*.json）。
  static Future<int> clearAll() async {
    final dir = await getApplicationSupportDirectory();
    var count = 0;
    try {
      await for (final ent in dir.list()) {
        final name = ent.path.split(Platform.pathSeparator).last;
        if (ent is File &&
            name.startsWith('cover_') &&
            name.endsWith('.json')) {
          await ent.delete();
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// 全量重建：扫描所有人物封面 + 作品封面，读图头拿宽高比，写字典。
  static Future<Map<String, double>> rebuild(
      SmbCreds c, String share, StylesConfig config) async {
    final map = <String, double>{};

    for (final style in config.allRegistered) {
      final stylePath = '$share/$style';
      List<PersonNode> people;
      try {
        people = await PersonRepo.listPeople(c, stylePath);
      } catch (_) {
        continue;
      }
      for (final p in people) {
        bool group = false;
        try {
          group = await PersonRepo.isGroup(c, p.path);
        } catch (_) {}
        final targets = <PersonNode>[];
        if (group) {
          // 团体封面本身也要（团体卡片用）
          await _coverFor(c, p.path, map);
          try {
            targets.addAll(await PersonRepo.listMembers(c, p.path));
          } catch (_) {}
        } else {
          targets.add(p);
        }
        for (final person in targets) {
          await _coverFor(c, person.path, map); // 人物封面 _cover.*
          await _workCoversFor(c, person, map); // 作品封面 .covers/*
        }
      }
    }

    await _write(share, map);
    return map;
  }

  // 人物/团体封面：尝试候选 _cover.{ext}，第一个能读到的解析尺寸
  static Future<void> _coverFor(
      SmbCreds c, String basePath, Map<String, double> out) async {
    for (final e in _coverExts) {
      final path = '$basePath/_cover.$e';
      final ar = await _aspectRatio(c, path);
      if (ar != null) {
        out[path] = ar;
        return; // 命中一个即止
      }
    }
  }

  // 作品封面：先 list 一次 .covers 目录拿到真实文件名，再在内存里为每个作品匹配
  // （封面名 = 作品全名 + 图片扩展名，忽略大小写）。
  // 这样每个人物只发 1 次 list + 每个有封面的作品 1 次读头，
  // 不再逐作品 × 多扩展名 × 大小写盲探测（那会把请求数放大几十倍 → 重建极慢）。
  static Future<void> _workCoversFor(
      SmbCreds c, PersonNode person, Map<String, double> out) async {
    List<String> works;
    try {
      works = await PersonRepo.listWorks(c, person.path);
    } catch (_) {
      return;
    }
    if (works.isEmpty) return;
    final dir = '${person.path}/.covers';

    // 一次性列出 .covers 里的真实文件（不存在/为空则没有作品封面，直接返回）
    List<SmbEntry> coverFiles;
    try {
      coverFiles = await SmbClient.list(c, dir);
    } catch (_) {
      return; // 没有 .covers 目录
    }
    if (coverFiles.isEmpty) return;

    // 建索引：封面文件名小写 → 真实文件名（保留原大小写用于拼路径）
    final byLower = <String, String>{};
    for (final e in coverFiles) {
      if (e.isDir) continue;
      byLower[e.name.toLowerCase()] = e.name;
    }

    final exts = _coverExts; // 图片扩展名集
    for (final f in works) {
      final base = f.toLowerCase(); // 作品全名（含原后缀，如 xxx.mp4）
      String? hitReal;
      for (final e in exts) {
        final cand = '$base.$e'; // 期望封面名：作品全名.扩展名
        final real = byLower[cand];
        if (real != null) {
          hitReal = real;
          break;
        }
      }
      if (hitReal == null) continue; // 该作品无封面
      final path = '$dir/$hitReal';
      final ar = await _aspectRatio(c, path);
      if (ar != null) out[path] = ar;
    }
  }

  // 读图头 → 宽高比。手动解析头部尺寸字节（不解码整图，截断数据也能拿尺寸）。
  static Future<double?> _aspectRatio(SmbCreds c, String path) async {
    try {
      final bytes = await SmbClient.readImageHeader(c, path);
      if (bytes == null || bytes.length < 24) return null;
      final wh = _parseDimensions(bytes);
      if (wh != null) {
        final w = wh[0], h = wh[1];
        if (w > 0 && h > 0) return w / h;
      }
      // 兜底：少见格式（heic/bmp 等）才尝试解码（可能因截断失败，返回 null）
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final w = frame.image.width, h = frame.image.height;
        frame.image.dispose();
        codec.dispose();
        if (w > 0 && h > 0) return w / h;
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  // 从头部字节解析 [宽, 高]；无法识别返回 null
  static List<int>? _parseDimensions(List<int> b) {
    final n = b.length;
    // PNG: 89 50 4E 47 ... IHDR 宽高在 16~24 字节（big-endian）
    if (n >= 24 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return [w, h];
    }
    // GIF: 'GIF8' 宽高在 6~10 字节（little-endian）
    if (n >= 10 &&
        b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
      final w = b[6] | (b[7] << 8);
      final h = b[8] | (b[9] << 8);
      return [w, h];
    }
    // WebP: 'RIFF'....'WEBP'
    if (n >= 30 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      final fmt = String.fromCharCodes(b.sublist(12, 16));
      if (fmt == 'VP8 ') {
        // 简单有损：尺寸在 26~30（14 位）
        final w = ((b[26] | (b[27] << 8)) & 0x3FFF);
        final h = ((b[28] | (b[29] << 8)) & 0x3FFF);
        return [w, h];
      } else if (fmt == 'VP8L') {
        // 无损：21~25 打包 14 位
        final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
        final w = (bits & 0x3FFF) + 1;
        final h = ((bits >> 14) & 0x3FFF) + 1;
        return [w, h];
      } else if (fmt == 'VP8X' && n >= 30) {
        // 扩展：24~27 / 27~30 各 24 位 +1
        final w = ((b[24] | (b[25] << 8) | (b[26] << 16)) & 0xFFFFFF) + 1;
        final h = ((b[27] | (b[28] << 8) | (b[29] << 16)) & 0xFFFFFF) + 1;
        return [w, h];
      }
    }
    // JPEG: FF D8 ... 扫描 SOF 段拿宽高
    if (n >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < n) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        // SOF0..SOF15（排除 DHT/JPG/DAC = C4/C8/CC）
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          // 段：FF marker len(2) precision(1) height(2) width(2)
          final h = (b[i + 5] << 8) | b[i + 6];
          final w = (b[i + 7] << 8) | b[i + 8];
          return [w, h];
        }
        // 跳到下一段：长度在 marker 后两字节
        final segLen = (b[i + 2] << 8) | b[i + 3];
        if (segLen <= 0) break;
        i += 2 + segLen;
      }
    }
    return null;
  }
}