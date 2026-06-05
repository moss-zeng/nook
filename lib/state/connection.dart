import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
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

  /// 断开连接：清除已保存的配置，状态重置（Link 回到 + 状态）
  Future<void> disconnect() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('host');
    await p.remove('user');
    await p.remove('pass');
    state = const ConnectionData(loaded: true);
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
  void set(String? v) {
    state = v;
    // 换 share：若处于随机配色模式，刷新随机种子（重进/换 share 颜色重随机）
    ref.read(personColorModeProvider.notifier).bumpSeed();
  }
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

/// LinkPage 是否处于"新建连接表单"态：是则 HomeShell 的返回键先收回到 + 按钮
class LinkFormOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final linkFormOpenProvider =
    NotifierProvider<LinkFormOpenNotifier, bool>(
  LinkFormOpenNotifier.new,
);

/// 当前打开的库是否风格库（ViewPage 判定后写入，shell 据此显示搜索按钮）
class IsStyleLibraryNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final isStyleLibraryProvider =
    NotifierProvider<IsStyleLibraryNotifier, bool>(
  IsStyleLibraryNotifier.new,
);

/// View 风格库是否已"开箱完成"（shell 据此决定搜索按钮出现时机）
class ViewSceneReadyNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final viewSceneReadyProvider =
    NotifierProvider<ViewSceneReadyNotifier, bool>(
  ViewSceneReadyNotifier.new,
);

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

/// 当前 View 层级的强调色号（1~20）；null = 用默认（搜索按钮 View_C.surface 底）。
/// 人物/作品/团体面板进入时写入对应色号，退出恢复，shell 搜索按钮据此变底色。
class ViewAccentNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? v) => state = v;
}

final viewAccentProvider =
    NotifierProvider<ViewAccentNotifier, int?>(ViewAccentNotifier.new);

/// 人物配色模式：false=按人名 hash 固定（默认）；true=随机（同 share 一致，换/重进 share 重随机）。
/// 随机用 share 级种子叠加到 hash 上做整体平移（色族关系不变）。
class PersonColorModeNotifier extends Notifier<bool> {
  static int _seed = 0; // 静态：跨重建保留
  int get seed => _seed;

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool('personColorRandom') ?? false;
    if (v != state) state = v;
  }

  Future<void> setRandom(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('personColorRandom', v);
    if (v) _seed++; // 切到随机：刷新种子立即产生新随机
    state = v; // 值变化会通知依赖刷新
  }

  // 随机种子：换/重进 share 时 +1（仅随机模式有意义）。
  // 通过给 selectedShare 之外的依赖发通知——这里用一个计数 state 配合。
  void bumpSeed() {
    if (!state) return; // 非随机模式无需刷新
    _seed++;
    ref.read(colorSeedTickProvider.notifier).bump();
  }
}

final personColorModeProvider =
    NotifierProvider<PersonColorModeNotifier, bool>(
  PersonColorModeNotifier.new,
);

/// 随机种子变化计数：watch 它即可在种子变化时重算颜色（值不变也能触发刷新）。
class ColorSeedTickNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

final colorSeedTickProvider =
    NotifierProvider<ColorSeedTickNotifier, int>(ColorSeedTickNotifier.new);

/// 计算人物色号：hash 模式直接用人名 hash；随机模式叠加 share 级随机偏移。
int personColorIdx(WidgetRef ref, String name, String? share) {
  final random = ref.watch(personColorModeProvider);
  ref.watch(colorSeedTickProvider); // 随种子变化重算
  final base = Style_C.idxOf(name);
  if (!random || share == null) return base;
  final seed = ref.read(personColorModeProvider.notifier).seed;
  final offset = ('$share#$seed').hashCode.abs() % 20;
  return Style_C.norm(base + offset);
}

/// "如何算某个对象的根色号"的描述（颜色不存 int 副本，按需现场算活值）。
/// - 单人：personName 即可。
/// - 团员：groupName + memberIndex（团员色 = 团体根色 +1 +顺位）。
class PersonColorSpec {
  final String? personName; // 单人
  final String? groupName; // 团员所属团体
  final int memberIndex; // 团员顺位（0 起）
  const PersonColorSpec.person(String name)
      : personName = name,
        groupName = null,
        memberIndex = 0;
  const PersonColorSpec.member(String group, int index)
      : personName = null,
        groupName = group,
        memberIndex = index;

  /// 现场算根色号（活值，随模式/种子变化）。
  int resolve(WidgetRef ref, String? share) {
    if (groupName != null) {
      final g = personColorIdx(ref, groupName!, share);
      return Style_C.norm(g + 1 + memberIndex);
    }
    return personColorIdx(ref, personName ?? '', share);
  }
}