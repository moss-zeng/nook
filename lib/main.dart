import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme.dart';
import 'shell.dart';
import 'pages/link_page.dart';
import 'pages/view_page.dart';
import 'pages/keep_page.dart';
import 'pages/settings_page.dart';

void main() => runApp(const ProviderScope(child: NookApp()));

// View 分支的 Navigator key：用于从 Link 切 share 时清掉 View 分支的 push 栈
final viewNavKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  initialLocation: '/link',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/link', builder: (_, __) => const LinkPage()),
        ]),
        StatefulShellBranch(navigatorKey: viewNavKey, routes: [
          GoRoute(path: '/view', builder: (_, __) => const ViewPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/keep', builder: (_, __) => const KeepPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
        ]),
      ],
    ),
  ],
);

class NookApp extends StatelessWidget {
  const NookApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'nook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.accent,
          surface: C.bg, 
        ),
        fontFamily: 'Roboto',
      ),
      routerConfig: _router,
    );
  }
}
