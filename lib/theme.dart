import 'package:flutter/material.dart';

/// 浅色主体色
class C {
  static const bg = Color(0xFFF7F8FA); // 近白浅灰背景
  static const surface = Color(0xFFFFFFFF); // 卡片/栏白
  static const accent = Color(0xFF2D5BD0); // 蓝色点缀
  static const accentSoft = Color(0xFFE3EAFB); // 浅蓝方块
  static const ink = Color(0xFF1A1C20); // 主文字
  static const inkSoft = Color(0xFF8A9099); // 次要文字/未选图标
  static const line = Color(0xFFE9ECF0); // 细分隔线
  static const barBg = Color(0xFFEFF1F4); // 底部栏底色
}

// 浅黄Link_C配色
class Link_C {
  static const bg = Color(0xFFFFFCF5);
  static const surface = Color(0xFFFAF3E0);
  static const accent = Color(0xFFE3D9BA);
  static const ink = Color(0xFF9D6E56);
  static const inkSoft = Color(0xFFCFAF64);
  static const line = Color(0xFFEFE3C4);
  static const barBg = Color(0xFFE7D3A1);
}

// 浅蓝View_C配色
class View_C{
  static const bg = Color(0xFFF7FAFF);
  static const surface = Color(0xFFEAF0FA);
  static const accent = Color(0xFF5E84BE);
  static const ink = Color(0xFF586673);
  static const inkSoft = Color(0xFF6C6F79);
  static const line = Color(0xFFDDE6F2); 
  static const barBg = Color(0xFF8FAFD8);
}



/// 浅粉Keep配色
class Keep_C {
  static const bg = Color(0xFFFBF4F5);
  static const surface = Color(0xFFF4E3E6);
  static const ink = Color(0xFF814A64);
  static const inkSoft = Color(0xFFCC857B);
  static const barBg = Color(0xFFDCAEC1);
  static const letterMid = Color(0xFFFFE6EF);
  static const letterDeep = Color(0xFFFFC1D9);
}

// 爱心颜色
class Heart_C {
  Heart_C._();

  // 空心描边
  static const stroke = Color(0xFFE8C2C8);

  // 粉心渐变（浅 -> 深）
  static const pinkStart = Color(0xFFFFA8B9);
  static const pinkEnd = Color(0xFFF56B8A);

  // 火焰渐变（正红 -> 红橙 -> 橙黄）
  static const flameInner = Color(0xFFFF2A50);
  static const flameMid = Color(0xFFFF4A30);
  static const flameOuter = Color(0xFFFF8F00);
}

// 胶囊配色
class Style_C {

  // ====================== 1. 柔粉系（柔粉）3色 ======================
  static const bg1 = Color(0xFFF9EAEC); // 柔粉1
  static const ink1 = Color(0xFF785A5F);
  static const bg2 = Color(0xFFF7E7E9); // 柔粉2
  static const ink2 = Color(0xFF75575C);
  static const bg3 = Color(0xFFF5E4E6); // 柔粉3
  static const ink3 = Color(0xFF725459);

  // ====================== 2. 烟紫系（烟紫）3色 ======================
  static const bg4 = Color(0xFFF0E1E6); // 烟紫1
  static const ink4 = Color(0xFF6B525C);
  static const bg5 = Color(0xFFEBDFE7); // 烟紫2
  static const ink5 = Color(0xFF66505F);
  static const bg6 = Color(0xFFE6DCE8); // 烟紫3
  static const ink6 = Color(0xFF614E62);

  // ====================== 3. 雾紫蓝系（雾紫蓝）3色 ======================
  static const bg7 = Color(0xFFE4DFE9); // 雾紫蓝1
  static const ink7 = Color(0xFF5E5565);
  static const bg8 = Color(0xFFE3E1EB); // 雾紫蓝2
  static const ink8 = Color(0xFF5B5768);
  static const bg9 = Color(0xFFE1E3ED); // 雾紫蓝3
  static const ink9 = Color(0xFF58596B);

  // ====================== 4. 雾青蓝系（雾青蓝）3色 ======================
  static const bg10 = Color(0xFFDFE5EE); // 雾青蓝1
  static const ink10 = Color(0xFF555B6E);
  static const bg11 = Color(0xFFDDE6EF); // 雾青蓝2
  static const ink11 = Color(0xFF525D71);
  static const bg12 = Color(0xFFDBE8F0); // 雾青蓝3
  static const ink12 = Color(0xFF4F5F74);

  // ====================== 5. 薄荷绿系（薄荷绿）3色 ======================
  static const bg13 = Color(0xFFDCE9ED); // 薄荷绿1
  static const ink13 = Color(0xFF4C6171);
  static const bg14 = Color(0xFFDDEAEA); // 薄荷绿2
  static const ink14 = Color(0xFF49636E);
  static const bg15 = Color(0xFFDEEBE7); // 薄荷绿3
  static const ink15 = Color(0xFF46656B);

  // ====================== 6. 浅黄绿系（浅黄绿）2色 ======================
  static const bg16 = Color(0xFFE3EBE2); // 浅黄绿1
  static const ink16 = Color(0xFF496662);
  static const bg17 = Color(0xFFE8EBDB); // 浅黄绿2
  static const ink17 = Color(0xFF4C6759);

  // ====================== 7. 暖杏系（暖杏）3色 ======================
  static const bg18 = Color(0xFFF0EBD5); // 暖杏1
  static const ink18 = Color(0xFF556450);
  static const bg19 = Color(0xFFF5EEDB); // 暖杏2
  static const ink19 = Color(0xFF5D6852);
  static const bg20 = Color(0xFFF9F1E1); // 暖杏3
  static const ink20 = Color(0xFF656C54);
  // bg20 → bg1 ΔE=3.9（≤5）

  // ===== 取色工具（n 从 1 开始，自动环绕 1~20）=====
  static const List<Color> _bgs = [
    bg1, bg2, bg3, bg4, bg5, bg6, bg7, bg8, bg9, bg10,
    bg11, bg12, bg13, bg14, bg15, bg16, bg17, bg18, bg19, bg20,
  ];
  static const List<Color> _inks = [
    ink1, ink2, ink3, ink4, ink5, ink6, ink7, ink8, ink9, ink10,
    ink11, ink12, ink13, ink14, ink15, ink16, ink17, ink18, ink19, ink20,
  ];

  /// 规整色号到 1~20（环绕）
  static int norm(int n) => ((n - 1) % 20 + 20) % 20 + 1;

  /// 取背景色（n 从 1 开始）
  static Color bg(int n) => _bgs[norm(n) - 1];

  /// 取文字色（n 从 1 开始）
  static Color ink(int n) => _inks[norm(n) - 1];

  /// 由名字稳定地映射到一个色号（1~20）。同名恒定同色。
  static int idxOf(String name) => (name.hashCode.abs() % 20) + 1;

  /// 在 center 附近 ±span 内，由 seed 稳定取一个色号（用于子层色族扩散）。
  /// 例：作品 = around(人物色号, 文件名, span:2) → 在 [center-2, center+2] 取。
  static int around(int center, String seed, {int span = 2}) {
    final range = span * 2 + 1; // 候选数量
    final offset = (seed.hashCode.abs() % range) - span; // [-span, +span]
    return norm(center + offset);
  }
}