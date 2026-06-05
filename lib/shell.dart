import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'theme.dart';
import 'widgets.dart';
import 'state/connection.dart';
import 'pages/search_page.dart';


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
        Dest.link => Symbols.share,
        Dest.view => Symbols.folder_open,
        Dest.keep => Symbols.favorite,
        Dest.settings => Symbols.tune,
      };

  String get path => switch (this) {
        Dest.link => '/link',
        Dest.view => '/view',
        Dest.keep => '/keep',
        Dest.settings => '/settings',
      };
}

/// 每个页面的主题色三件套：页面背景 / 底栏底色 / 强调(选中图标+汉堡)
/// 用一个轻量对象打包，避免 Link_C/View_C/Keep_C 是不同 class 无法统一引用的问题。
class _PageTheme {
  final Color bg;       // 顶栏背景
  final Color surface;  // 底栏底色
  final Color barBg;    // 选中图标 + 汉堡图标
  const _PageTheme({required this.bg, required this.surface, required this.barBg});
}

/// 根据当前页取主题色。settings 不在底栏内，回退到全局 C。
_PageTheme _themeFor(Dest d) {
  switch (d) {
    case Dest.link:
      return const _PageTheme(bg: Link_C.bg, surface: Link_C.surface, barBg: Link_C.barBg);
    case Dest.view:
      return const _PageTheme(bg: View_C.bg, surface: View_C.surface, barBg: View_C.barBg);
    case Dest.keep:
      return const _PageTheme(bg: Keep_C.bg, surface: Keep_C.surface, barBg: Keep_C.barBg);
    case Dest.settings:
      return const _PageTheme(bg: C.bg, surface: C.barBg, barBg: C.accent);
  }
}

class MinimalSearchIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const MinimalSearchIcon({
    super.key,
    this.color = Colors.black,
    this.size = 24,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MinimalSearchPainter(
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _MinimalSearchPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _MinimalSearchPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.45, size.height * 0.45);
    final radius = size.width * 0.4;

    canvas.drawCircle(center, radius, paint);

    final handleStart = Offset(
      center.dx + radius * 0.707,
      center.dy + radius * 0.707,
    );
    final handleEnd = Offset(
      handleStart.dx + size.width * 0.25,
      handleStart.dy + size.height * 0.25,
    );
    canvas.drawLine(handleStart, handleEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _MinimalSearchPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}

/// 外壳：包住底部三栏页面。navigationShell 由 go_router 提供
class HomeShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const HomeShell({super.key, required this.navigationShell});

  static const _scaffoldKey = GlobalObjectKey<ScaffoldState>('nook_shell');

  static const _allDests = [Dest.link, Dest.view, Dest.keep, Dest.settings];
  static const _bottomDests = [Dest.link, Dest.view, Dest.keep];

  Dest get _current => _allDests[navigationShell.currentIndex];

  void _goBranch(WidgetRef ref, Dest d) {
    final idx = _allDests.indexOf(d);
    navigationShell.goBranch(idx,
        initialLocation: idx == navigationShell.currentIndex);
    if (d == Dest.view) {
      ref.read(viewRefreshProvider.notifier).bump();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = _themeFor(_current); // 当前页配色
    // LinkPage 是否处于"新建连接表单"态：是则返回键先收回到 + 按钮
    final linkFormOpen = ref.watch(linkFormOpenProvider);

    return PopScope(
      canPop: false, // 始终不让系统返回直接退出 App
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 在 Link 页的新建表单态时，返回收回到 +（关闭表单）
        if (_current == Dest.link && linkFormOpen) {
          ref.read(linkFormOpenProvider.notifier).set(false);
        }
      },
      // 大背景随页面平滑过渡（与顶/底栏的 400ms 过渡同步）
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: theme.bg),
        duration: const Duration(milliseconds: 400),
        builder: (context, animatedBg, child) => Scaffold(
          key: _scaffoldKey,
          backgroundColor: animatedBg,
          resizeToAvoidBottomInset: false,
          drawer: _NookDrawer(
            current: _current,
            onSelect: (d) {
              Navigator.of(context).pop();
              _goBranch(ref, d);
            },
          ),
          body: child,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _TopBar(
                    currentIndex: navigationShell.currentIndex,
                    bgColor: theme.bg,        // 顶栏背景随页面
                    menuColor: theme.barBg,   // 当前页汉堡色
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
              // 搜索按钮（方案b）：常驻挂载，用淡入+IgnorePointer 控制显隐，
              // 不随 ready 增删 widget → 不在切换帧做挂载/首次 paint，不抢帧
              Positioned(
                right: 20,
                bottom: 96,
                child: Builder(builder: (context) {
                  final visible = ref.watch(isStyleLibraryProvider) &&
                      _current == Dest.view &&
                      ref.watch(viewSceneReadyProvider);
                  // 底色：默认 View_C.surface；进入人物/作品/团体时跟随其色号
                  final accentIdx = ref.watch(viewAccentProvider);
                  final btnColor = accentIdx == null
                      ? View_C.surface
                      : Style_C.bg(accentIdx);
                  return IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: visible ? 1.0 : 0.0,
                      child: InkWell(
                        onTap: () {
                          final creds = ref.read(connectionProvider).creds;
                          final share = ref.read(selectedShareProvider);
                          if (creds == null || share == null) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                SearchPage(creds: creds, share: share),
                          )).then((_) {
                            // 从搜索页返回：accent 归位（回到第一/二层默认色）
                            ref.read(viewAccentProvider.notifier).set(null);
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          width: 55,
                          height: 55,
                          decoration: BoxDecoration(
                            color: btnColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: MinimalSearchIcon(
                              color: C.inkSoft,
                              size: 30,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _BottomBar(
                  dests: _bottomDests,
                  current: _current,
                  barColor: theme.surface,      // 底栏底色随页面 surface
                  selectedColor: theme.barBg,   // 选中图标随页面 barBg
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

class _TopBar extends StatefulWidget {
  final int currentIndex;        // 当前页索引（用于判断左切/右切）
  final VoidCallback onMenu;
  final Color bgColor;           // 顶栏背景（当前页 bg）
  final Color menuColor;         // 当前页汉堡色（barBg）
  const _TopBar({
    required this.currentIndex,
    required this.onMenu,
    required this.bgColor,
    required this.menuColor,
  });
  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> with SingleTickerProviderStateMixin {
  // ====== 可调参数 ======
  static const _duration = Duration(milliseconds: 520); // 整段动画总时长
  static const _flyDistance = 26.0; // 飞行位移像素
  static const _outEnd = 0.55;      // 旧汉堡在 [0, _outEnd] 飞走
  static const _inStart = 0.38;     // 新汉堡从 _inStart 开始飞入（与飞走有重叠/时间差）
  // =====================

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _duration);

  late int _prevIndex = widget.currentIndex;
  late Color _prevColor = widget.menuColor; // 旧汉堡的颜色
  int _dir = 1; // 1=左切(索引变大) -1=右切(索引变小)

  @override
  void didUpdateWidget(_TopBar old) {
    super.didUpdateWidget(old);
    if (widget.currentIndex != _prevIndex) {
      _dir = widget.currentIndex > _prevIndex ? 1 : -1;
      _prevColor = old.menuColor;     // 上一页的汉堡色
      _ctrl.forward(from: 0).whenComplete(() {
        // 动画结束后把"旧色"对齐成当前色，回到稳定态
        if (mounted) setState(() => _prevColor = widget.menuColor);
      });
      _prevIndex = widget.currentIndex;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 顶栏背景平滑过渡
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.bgColor),
      duration: const Duration(milliseconds: 400),
      builder: (context, bg, _) {
        return Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              _buildMenu(),
              const Spacer(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenu() {
    // 左切(_dir=1)：旧的往左上飞走，新的从右下飞入；右切则镜像
    // 左上 = (-x,-y)，右下 = (+x,+y)
    final outOffsetSign = _dir == 1 ? -1.0 : 1.0; // 旧汉堡飞走方向
    final inOffsetSign = -outOffsetSign;          // 新汉堡来向（相反角）

    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          // 旧汉堡：[0, _outEnd] 内从中心飞向一角并渐隐
          final outT = (t / _outEnd).clamp(0.0, 1.0);
          final outEased = Curves.easeIn.transform(outT);
          final outDx = outOffsetSign * _flyDistance * outEased;
          final outDy = outOffsetSign * _flyDistance * outEased;
          final outOpacity = 1.0 - outEased;

          // 新汉堡：[_inStart, 1] 内从相反角飞回中心并渐显
          final inT = ((t - _inStart) / (1 - _inStart)).clamp(0.0, 1.0);
          final inEased = Curves.easeOut.transform(inT);
          final inDx = inOffsetSign * _flyDistance * (1 - inEased);
          final inDy = inOffsetSign * _flyDistance * (1 - inEased);
          final inOpacity = inEased;

          final animating = _ctrl.isAnimating;

          return Stack(
            alignment: Alignment.center,
            children: [
              // 旧色汉堡（飞走）—— 仅动画期间显示
              if (animating)
                Opacity(
                  opacity: outOpacity,
                  child: Transform.translate(
                    offset: Offset(outDx, outDy),
                    child: Icon(Icons.menu, color: _prevColor),
                  ),
                ),
              // 新色汉堡（飞入 / 稳定态）
              Opacity(
                opacity: animating ? inOpacity : 1.0,
                child: Transform.translate(
                  offset: animating ? Offset(inDx, inDy) : Offset.zero,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onMenu,
                    child: Icon(Icons.menu, color: widget.menuColor),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<Dest> dests;
  final Dest current;
  final ValueChanged<Dest> onSelect;
  final Color barColor;       // 底栏底色
  final Color selectedColor;  // 选中图标色
  const _BottomBar({
    super.key,
    required this.dests,
    required this.current,
    required this.onSelect,
    required this.barColor,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: barColor),
      duration: const Duration(milliseconds: 400),
      builder: (context, animatedBar, child) => Container(
        height: 70,
        decoration: BoxDecoration(
          color: animatedBar, // 随页面 surface，平滑过渡
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: dests.map((d) {
          final selected = d == current;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(d),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: selected
                        ? Curves.easeOutCubic
                        : const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
                    margin: EdgeInsets.only(top: selected ? 0 : 2),
                    padding: EdgeInsets.only(bottom: selected ? 2 : 0),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 400),
                      curve: selected
                          ? Curves.easeOutCubic
                          : const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
                      scale: selected ? 0.92 : 1.0,
                      // 选中=页面 barBg+实心；未选=灰+空心
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                            end: selected ? selectedColor : C.inkSoft),
                        duration: const Duration(milliseconds: 400),
                        builder: (context, iconColor, _) => Icon(
                          d.icon,
                          color: iconColor,
                          size: 26,
                          fill: selected ? 1 : 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    curve: selected
                        ? const Interval(0.3, 1.0, curve: Curves.easeOut)
                        : Curves.easeIn,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 12,
                      height: 6,
                      decoration: BoxDecoration(
                        color: selectedColor, // 小圆点也随页面
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
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
              Icon(
                d.icon,
                color: selected ? Colors.white : C.ink,
                size: 22,
                fill: selected ? 1 : 0,
              ),
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
      )
    );
  }
}