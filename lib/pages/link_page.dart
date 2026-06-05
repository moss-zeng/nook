import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';
import '../widgets.dart';
import '../smb/smb_client.dart';
import '../state/connection.dart';
import '../main.dart';

class LinkPage extends ConsumerStatefulWidget {
  const LinkPage({super.key});
  @override
  ConsumerState<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends ConsumerState<LinkPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _formOpen = false; // 无配置时 + 是否已展开
  bool _filled = false; // 是否已把存储值填进输入框
  bool _wasConfigured = false; // 上一帧是否有配置（用于检测 disconnect）
  bool _connecting = false; // 连接进行中（防重入 + loading）
  bool _hostNotEmpty = false; // host 是否非空（按钮可用性的唯一依据）
  double _lastBottomInset = 0;
  late final AnimationController _expandCtrl;
  late final AnimationController _fadeCtrl;
  bool _anyFocused = false;
  bool _buttonClickable = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _host.addListener(_onHostChanged);
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _fadeCtrl.forward();
    });
    _fadeCtrl.addStatusListener((s) {
      final ok = s == AnimationStatus.completed;
      if (ok != _buttonClickable) setState(() => _buttonClickable = ok);
    });
  }

  // host 内容变化时，更新明确的状态位（不在 build 里临时读 controller）
  void _onHostChanged() {
    final notEmpty = _host.text.trim().isNotEmpty;
    if (notEmpty != _hostNotEmpty) {
      setState(() => _hostNotEmpty = notEmpty);
    }
  }

  void _onFocusChange(bool hasFocus) {
    _anyFocused = hasFocus;
    if (hasFocus) {
      // 键盘弹出 → 同时收缩 + 淡出
      setState(() => _buttonClickable = false);
      _fadeCtrl.reverse();
      _expandCtrl.reverse();
    } else {
      // 键盘收起 → host 非空才展开
      if (_hostNotEmpty) {
        _expandCtrl.forward();
      }
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      if (_lastBottomInset > 0 && bottomInset == 0 && _anyFocused) {
        FocusScope.of(context).unfocus();
      }
      _lastBottomInset = bottomInset;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expandCtrl.dispose();
    _fadeCtrl.dispose();
    _host.removeListener(_onHostChanged);
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  // 同步"新建表单态"到全局 provider，供 HomeShell 返回键判断
  void _setFormOpen(bool open) {
    setState(() => _formOpen = open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(linkFormOpenProvider.notifier).set(open);
    });
  }

  void _syncFromConfig(ConnectionData conn) {
    // 检测 disconnect：从有配置 -> 无配置，重置一次回 + 状态
    if (_wasConfigured && !conn.hasConfig) {
      _filled = false;
      _formOpen = false;
      _host.clear();
      _user.clear();
      _pass.clear();
      _hostNotEmpty = false;
      _expandCtrl.value = 0.0;
      _fadeCtrl.value = 0.0;
      _buttonClickable = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(linkFormOpenProvider.notifier).set(false);
      });
    }
    _wasConfigured = conn.hasConfig;

    // 首次：把已存配置填进输入框
    if (!_filled && conn.hasConfig && conn.creds != null) {
      _host.text = conn.creds!.host;
      _user.text = conn.creds!.user;
      _pass.text = conn.creds!.pass;
      _formOpen = true;
      _hostNotEmpty = _host.text.trim().isNotEmpty;
      _expandCtrl.value = 1.0;
      _fadeCtrl.value = 1.0;
      _buttonClickable = true;
      _filled = true;
      // 已有配置不是"新建表单态"，返回键无需收回
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(linkFormOpenProvider.notifier).set(false);
      });
    }
  }

  Future<void> _connect() async {
    if (_connecting) return; // 防重入
    final host = _host.text.trim();
    if (host.isEmpty) return; // host 必填

    FocusScope.of(context).unfocus();
    setState(() => _connecting = true);

    final c = SmbCreds(host, _user.text.trim(), _pass.text);
    try {
      await ref.read(connectionProvider.notifier).connect(c);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  // 底部 SnackBar（贴底，非悬浮），先清旧的避免叠加
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Link_C.ink)),
          backgroundColor: Link_C.surface,
          behavior: SnackBarBehavior.fixed, // 贴底，铺满底部
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);

    // 监听返回键等外部把表单态置 false：同步关闭本地 _formOpen（回到 +）
    ref.listen<bool>(linkFormOpenProvider, (prev, next) {
      if (next == false && _formOpen && !conn.hasConfig) {
        setState(() => _formOpen = false);
      }
    });

    if (!conn.loaded) {
      return const SizedBox.shrink();
    }
    _syncFromConfig(conn);

    // 连接进行中：整页只显示一个居中 loading（Link_C 配色）
    if (_connecting) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Link_C.accent),
        ),
      );
    }

    // 已连接：显示 shares 网格
    if (conn.connected) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: _sharesGrid(conn.shares),
      );
    }

    // 未连接：+ 或 连接表单
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: (!conn.hasConfig && !_formOpen)
            ? _addButton(
                icon: Icons.add,
                onTap: () => _setFormOpen(true),
              )
            : _connForm(),
      ),
    );
  }

  Widget _addButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Link_C.barBg, // 奶黄底
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Link_C.ink, size: 24),
        ),
      ),
    );
  }

  Widget _connForm() {
    return Focus(
      canRequestFocus: false,
      onFocusChange: _onFocusChange,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Link_C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Link_C.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_host, 'Host', Icons.dns_outlined),
            const SizedBox(height: 12),
            _field(_user, 'Username', Icons.person_outline),
            const SizedBox(height: 12),
            _field(_pass, 'Password', Icons.lock_outline, obscure: true),
            SizeTransition(
              sizeFactor: _expandCtrl,
              axisAlignment: -1.0,
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: IgnorePointer(
                      ignoring: !_buttonClickable,
                      child: TextButton(
                        onPressed: _connect,
                        style: TextButton.styleFrom(
                          backgroundColor: Link_C.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Connect',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Link_C.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Link_C.inkSoft),
        prefixIcon: Icon(icon, color: Link_C.inkSoft, size: 20),
        filled: true,
        fillColor: Link_C.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _sharesGrid(List<String> shares) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shares.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (_, i) => _shareCard(shares[i]),
    );
  }

  Widget _shareCard(String name) {
    return Material(
      color: Link_C.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final viewNav = viewNavKey.currentState;
          if (viewNav != null && viewNav.canPop()) {
            viewNav.popUntil((route) => route.isFirst);
          }
          ref.read(selectedShareProvider.notifier).set(name);
          context.go('/view');
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Link_C.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_outlined, color: Link_C.inkSoft, size: 40),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Link_C.ink, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}