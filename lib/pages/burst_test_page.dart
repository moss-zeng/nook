import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// 纯测试页：只播放 heart_burst.json，不加任何尺寸约束/按钮/Stack。
/// 用途：判断"爆炸不完整"到底是动画文件本身的问题，还是布局代码的问题。
///
/// 怎么用（任选其一，临时即可）：
///   1) 在某个按钮 onTap 里：
///        Navigator.of(context).push(MaterialPageRoute(
///          builder: (_) => const BurstTestPage()));
///   2) 或临时把某页 build 直接 return const BurstTestPage();
///
/// 看到什么：
///   - 动画循环播放。若【完整】→ 说明是我们的布局代码裁切/遮挡，继续查代码。
///   - 若【仍然不完整】→ 说明是 heart_burst.json 这个文件本身画布(composition)
///     就把爆炸碎片裁掉了，需要重新导出（放大画布）。
///
/// 页面提供 3 种呈现，对照看：
///   A. 完全不限制尺寸（Lottie 用 composition 原始大小，最能反映文件真实样子）
///   B. 限制到 200（和 keep 里按钮一样大）
///   C. 限制到 320 + BoxFit.contain（和当前 keep 爆开层一样）
class BurstTestPage extends StatelessWidget {
  const BurstTestPage({super.key});

  static const String _asset = 'assets/heart_burst.json';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202020), // 深灰底，方便看清边缘
      appBar: AppBar(title: const Text('Burst Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('A. 无任何尺寸约束（文件原始大小，最真实）',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          // 不包 SizedBox：Lottie 用 composition 自身尺寸。repeat 循环播放。
          Center(
            child: Lottie.asset(_asset, repeat: true),
          ),
          const Divider(color: Colors.white24, height: 40),

          const Text('B. 限制 200×200（= keep 按钮大小）',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Lottie.asset(_asset, repeat: true, fit: BoxFit.contain),
            ),
          ),
          const Divider(color: Colors.white24, height: 40),

          const Text('C. 320×320 + contain（= 当前 keep 爆开层）',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: Lottie.asset(_asset, repeat: true, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}