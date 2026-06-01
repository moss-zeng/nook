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

class _LinkPageState extends ConsumerState<LinkPage> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _formOpen = false; // 无配置时 + 是否已展开
  bool _filled = false; // 是否已把存储值填进输入框

  void _fillFromConfig(ConnectionData conn) {
    if (_filled) return;
    if (conn.creds != null) {
      _host.text = conn.creds!.host;
      _user.text = conn.creds!.user;
      _pass.text = conn.creds!.pass;
      _formOpen = true;
    }
    _filled = true;
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final c = SmbCreds(_host.text.trim(), _user.text.trim(), _pass.text);
    try {
      await ref.read(connectionProvider.notifier).connect(c);
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Connection failed'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);

    if (!conn.loaded) {
      return const SizedBox.shrink();
    }
    _fillFromConfig(conn);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!conn.hasConfig && !_formOpen)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: SoftSquareButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _formOpen = true),
                ),
              ),
            )
          else if (conn.connected) ...[
            _sharesGrid(conn.shares),
          ] else ...[
            _connForm(),
          ],
        ],
      ),
    );
  }

  Widget _connForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.line),
      ),
      child: Column(
        children: [
          _field(_host, 'Host', Icons.dns_outlined),
          const SizedBox(height: 12),
          _field(_user, 'Username', Icons.person_outline),
          const SizedBox(height: 12),
          _field(_pass, 'Password', Icons.lock_outline, obscure: true),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _connect,
              style: TextButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: C.inkSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Connect',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: C.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: C.inkSoft),
        prefixIcon: Icon(icon, color: C.inkSoft, size: 20),
        filled: true,
        fillColor: C.bg,
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
      color: C.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // 清掉 View 分支内旧的 push 页（inbox/盲盒/子目录）
          final viewNav = viewNavKey.currentState;
          if (viewNav != null && viewNav.canPop()) {
            viewNav.popUntil((route) => route.isFirst);
          }
          // 选中该 share，跳到 View
          ref.read(selectedShareProvider.notifier).set(name);
          context.go('/view');
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_outlined, color: C.accent, size: 40),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: C.ink, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
