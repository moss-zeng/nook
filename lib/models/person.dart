import '../smb/smb_client.dart';

const _videoExt = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'rmvb', 'rm'
};

bool isVideoFile(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0) return false;
  return _videoExt.contains(name.substring(i + 1).toLowerCase());
}

bool isIgnoredEntry(String name) =>
    name.startsWith('_') || name.startsWith('.');

/// 一个人物 / 团体节点
class PersonNode {
  final String name;
  final String path; // 相对 share 根的完整路径
  const PersonNode({required this.name, required this.path});
}

class PersonRepo {
  /// 列出某风格文件夹下的人物 / 团体（只一次连接，不预判团体）
  static Future<List<PersonNode>> listPeople(
      SmbCreds c, String sharePlusStyle) async {
    final entries = await SmbClient.list(c, sharePlusStyle);
    return entries
        .where((e) => e.isDir && !isIgnoredEntry(e.name))
        .map((e) =>
            PersonNode(name: e.name, path: '$sharePlusStyle/${e.name}'))
        .toList();
  }

  /// 点击时即时判定：该路径是否团体（内部含子文件夹）
  static Future<bool> isGroup(SmbCreds c, String path) async {
    try {
      final inner = await SmbClient.list(c, path);
      return inner.any((e) => e.isDir && !isIgnoredEntry(e.name));
    } catch (_) {
      return false;
    }
  }

  /// 列出某团体下的成员
  static Future<List<PersonNode>> listMembers(
      SmbCreds c, String groupPath) async {
    final entries = await SmbClient.list(c, groupPath);
    return entries
        .where((e) => e.isDir && !isIgnoredEntry(e.name))
        .map((e) => PersonNode(name: e.name, path: '$groupPath/${e.name}'))
        .toList();
  }

  /// 列出某人物下的作品（视频文件名）
  static Future<List<String>> listWorks(SmbCreds c, String personPath) async {
    final entries = await SmbClient.list(c, personPath);
    return entries
        .where((e) => !e.isDir && isVideoFile(e.name))
        .map((e) => e.name)
        .toList();
  }
}
