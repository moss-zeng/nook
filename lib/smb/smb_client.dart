import 'dart:typed_data';
import 'package:flutter/services.dart';

/// SMB 连接凭据
class SmbCreds {
  final String host;
  final String user;
  final String pass;
  const SmbCreds(this.host, this.user, this.pass);
}

/// 目录条目
class SmbEntry {
  final String name;
  final bool isDir;
  const SmbEntry(this.name, this.isDir);
}

/// 封装与原生 jcifs 桥的所有交互
class SmbClient {
  static const _channel = MethodChannel('nook/smb');

  /// 列出服务器上的共享
  static Future<List<String>> listShares(SmbCreds c) async {
    final res = await _channel.invokeMethod<List<dynamic>>('listShares', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
    });
    return (res ?? []).cast<String>();
  }

  /// 列出某路径下条目。path 形如 "share/style1"，根用 "share"
  static Future<List<SmbEntry>> list(SmbCreds c, String path) async {
    final res = await _channel.invokeMethod<List<dynamic>>('list', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'path': path,
    });
    return (res ?? []).cast<String>().map((s) {
      final isDir = s.startsWith('[D] ');
      final name = s.length > 4 ? s.substring(4) : s;
      return SmbEntry(name, isDir);
    }).toList();
  }

  /// 读文本文件，不存在返回 null
  static Future<String?> readFile(SmbCreds c, String path) async {
    return await _channel.invokeMethod<String>('readFile', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'path': path,
    });
  }

  /// 写文本文件
  static Future<void> writeFile(SmbCreds c, String path, String content) async {
    await _channel.invokeMethod('writeFile', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'path': path,
      'content': content,
    });
  }

  /// 读图片字节，不存在返回 null
  static Future<Uint8List?> readImage(SmbCreds c, String path) async {
    return await _channel.invokeMethod<Uint8List>('readImage', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'path': path,
    });
  }

  /// 用外部播放器打开视频（发 smb:// 地址给系统/MX Player）
  static Future<void> openExternal(SmbCreds c, String path) async {
    await _channel.invokeMethod('openExternal', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'path': path,
    });
  }

  /// 移动或重命名：from/to 都是相对 share 根的完整路径（含 share 名）
  static Future<void> move(SmbCreds c, String from, String to) async {
    await _channel.invokeMethod('move', {
      'host': c.host,
      'user': c.user,
      'pass': c.pass,
      'from': from,
      'to': to,
    });
  }
}
