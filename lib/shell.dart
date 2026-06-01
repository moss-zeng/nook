import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme.dart';
import 'widgets.dart';
import 'state/connection.dart';

/// 导航目的地（用于底栏/抽屉）
enum Dest { link, view, keep, settings }

extension DestInfo on Dest {
  String get label => switch (this) {
        Dest.link => 'Link',
        Dest.view => 'View',
        Dest.keep => 'Keep',
        Dest.settings => 'Settings',
      };
  IconData get icon => switch (this) {
        Dest.link => Icons.pentagon_outlined,
        Dest.view => Icons.link_outlined,
        Dest.keep => Icons.favorite_border,
        Dest.settings => Icons.settings_outlined,
      };
  String get path => switch (this) {
        Dest.link => '/link',
        Dest.view => '/view',
        Dest.keep => '/keep',
        Dest.settings => '/settings',
      };
}

/// 外壳：包住底部三栏页面。navigationShell 由 go_router 提供
class HomeShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const HomeShell({super.key, required this.navigationShell});

  static const _scaffoldKey = GlobalObjectKey<ScaffoldState>('nook_shell');

  // 分支顺序必须与 router 中一致：link/view/keep/settings
  static const _allDests = [Dest.link, Dest.view, Dest.keep, Dest.settings];
  // 底部只显示前三个
  static const _bottomDests = [Dest.link, Dest.view, Dest.keep];

  Dest get _current => _allDests[navigationShell.currentIndex];

  void _goBranch(WidgetRef ref, Dest d) {
    final idx = _allDests.indexOf(d);
    navigationShell.goBranch(idx,
        initialLocation: idx == navigationShell.currentIndex);
    // 切到 View 时触发标签重新随机
    if (d == Dest.view) {
      ref.read(viewRefreshProvider.notifier).bump();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false, // 主壳不响应系统返回退出 App
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: C.bg,
        resizeToAvoidBottomInset: false,
        drawer: _NookDrawer(
          current: _current,
          onSelect: (d) {
            Navigator.of(context).pop();
            _goBranch(ref, d);
          },
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _TopBar(
                      onMenu: () => _scaffoldKey.currentState?.openDrawer()),
                  Expanded(child: navigationShell),
                ],
              ),
              Positioned(
                right: 20,
                bottom: 96,
                child: SoftSquareButton(icon: Icons.search, onTap: () {}),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _BottomBar(
                  dests: _bottomDests,
                  current: _current,
                  onSelect: (d) => _goBranch(ref, d),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onMenu;
  const _TopBar({required this.onMenu});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.menu, color: C.ink),
            splashRadius: 22,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<Dest> dests;
  final Dest current;
  final ValueChanged<Dest> onSelect;
  const _BottomBar({
    required this.dests,
    required this.current,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: C.barBg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: dests.map((d) {
          final selected = d == current;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                child: Icon(
                  d.icon,
                  color: selected ? C.accent : C.inkSoft,
                  size: 26,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NookDrawer extends StatelessWidget {
  final Dest current;
  final ValueChanged<Dest> onSelect;
  const _NookDrawer({required this.current, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: C.bg,
      elevation: 1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Navigation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: C.ink,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _item(Dest.link),
              const SizedBox(height: 8),
              _item(Dest.view),
              const SizedBox(height: 8),
              _item(Dest.keep),
              const SizedBox(height: 16),
              const Divider(color: C.line, height: 1),
              const SizedBox(height: 16),
              _item(Dest.settings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(Dest d) {
    final selected = d == current;
    return Material(
      color: selected ? C.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelect(d),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(d.icon, color: selected ? Colors.white : C.ink, size: 22),
              const SizedBox(width: 16),
              Text(
                d.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : C.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
