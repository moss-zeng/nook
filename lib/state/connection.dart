import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../smb/smb_client.dart';

/// 连接状态数据
class ConnectionData {
  final SmbCreds? creds;
  final bool hasConfig;
  final bool connected;
  final List<String> shares;
  final bool loaded;

  const ConnectionData({
    this.creds,
    this.hasConfig = false,
    this.connected = false,
    this.shares = const [],
    this.loaded = false,
  });

  ConnectionData copyWith({
    SmbCreds? creds,
    bool? hasConfig,
    bool? connected,
    List<String>? shares,
    bool? loaded,
  }) {
    return ConnectionData(
      creds: creds ?? this.creds,
      hasConfig: hasConfig ?? this.hasConfig,
      connected: connected ?? this.connected,
      shares: shares ?? this.shares,
      loaded: loaded ?? this.loaded,
    );
  }
}

class ConnectionNotifier extends Notifier<ConnectionData> {
  @override
  ConnectionData build() {
    _load();
    return const ConnectionData();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final h = p.getString('host');
    if (h != null && h.isNotEmpty) {
      state = state.copyWith(
        creds:
            SmbCreds(h, p.getString('user') ?? '', p.getString('pass') ?? ''),
        hasConfig: true,
        loaded: true,
      );
    } else {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _save(SmbCreds c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', c.host);
    await p.setString('user', c.user);
    await p.setString('pass', c.pass);
  }

  /// 连接（列 shares）。成功更新状态，失败抛异常给 UI
  Future<void> connect(SmbCreds c) async {
    final shares = await SmbClient.listShares(c);
    await _save(c);
    state = state.copyWith(
      creds: c,
      hasConfig: true,
      connected: true,
      shares: shares,
    );
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionData>(
  ConnectionNotifier.new,
);

/// 当前在 View 中选中的 share
class SelectedShareNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final selectedShareProvider =
    NotifierProvider<SelectedShareNotifier, String?>(
  SelectedShareNotifier.new,
);

/// View 刷新计数：每次切到 View 分支 +1，触发标签重新随机散布
class ViewRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

final viewRefreshProvider =
    NotifierProvider<ViewRefreshNotifier, int>(ViewRefreshNotifier.new);

/// 待移动的锁定项
class PendingMove {
  final String fromPath; // 相对 share 根的完整路径（含 share）
  final String name; // 文件/文件夹名
  final bool isDir;
  const PendingMove(
      {required this.fromPath, required this.name, required this.isDir});
}

class PendingMoveNotifier extends Notifier<PendingMove?> {
  @override
  PendingMove? build() => null;
  void lock(PendingMove p) => state = p;
  void clear() => state = null;
}

final pendingMoveProvider =
    NotifierProvider<PendingMoveNotifier, PendingMove?>(
  PendingMoveNotifier.new,
);
