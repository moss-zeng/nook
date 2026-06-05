import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'theme.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// 把 ISO 字符串(2022 / 2022-01 / 2022-01-02)格式化成 Jan 2, 2022
String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final parts = iso.split('-');
  final y = parts.isNotEmpty ? parts[0] : '';
  if (y.isEmpty) return iso;
  if (parts.length == 1) return y;
  final mi = int.tryParse(parts[1]);
  if (mi == null || mi < 1 || mi > 12) return y;
  final mName = _months[mi - 1];
  if (parts.length == 2) return '$mName $y';
  final d = int.tryParse(parts[2]);
  if (d == null) return '$mName $y';
  return '$mName $d, $y';
}

int _daysInMonth(int year, int month) {
  if (month == 2) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  if (const [4, 6, 9, 11].contains(month)) return 30;
  return 31;
}

/// 弹出 date 编辑器，返回 ISO 字符串；Reset 返回空字符串 ''；Cancel 返回 null。
/// colorIdx：配色色号（作品色），决定面板/强调色。
Future<String?> showDateEditor(BuildContext context, String? initial,
    {int colorIdx = 1}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (_) => _DateEditor(initial: initial, colorIdx: colorIdx),
  );
}

class _DateEditor extends StatefulWidget {
  final String? initial;
  final int colorIdx;
  const _DateEditor({this.initial, required this.colorIdx});
  @override
  State<_DateEditor> createState() => _DateEditorState();
}

enum _Active { none, month, day }

class _DateEditorState extends State<_DateEditor> {
  int? _year; // null = 未填
  int? _month; // null = None
  int? _day; // null = None
  _Active _active = _Active.none; // 当前哪个格在显示滚轮

  Color get _ink => Style_C.ink(widget.colorIdx);
  Color get _panelBg => Color.alphaBlend(
      Style_C.bg(widget.colorIdx).withOpacity(0.5), View_C.surface);
  Color get _cellBg => Style_C.bg(widget.colorIdx).withOpacity(0.35);

  @override
  void initState() {
    super.initState();
    final iso = widget.initial;
    if (iso != null && iso.isNotEmpty) {
      final p = iso.split('-');
      _year = p.isNotEmpty ? int.tryParse(p[0]) : null;
      if (p.length >= 2) _month = int.tryParse(p[1]);
      if (p.length >= 3) _day = int.tryParse(p[2]);
    }
  }

  void _editYear() async {
    setState(() => _active = _Active.none);
    final v = await _showYearInput(_year);
    if (v != null) {
      setState(() {
        _year = v;
        if (_month != null && _day != null) {
          final dim = _daysInMonth(_year!, _month!);
          if (_day! > dim) _day = dim;
        }
      });
    }
  }

  // 年份输入弹窗：失焦即保存（点别处收键盘自动提交），点外侧未输入则关闭
  Future<int?> _showYearInput(int? initial) {
    return showDialog<int>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      barrierDismissible: false,
      builder: (_) => _YearInput(
        colorIdx: widget.colorIdx,
        initial: initial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: _panelBg,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _cell(
                      child: Text(_year?.toString() ?? '____',
                          style: _cellStyle(_year != null)),
                      onTap: _editYear,
                      active: false,
                    ),
                    _sep(),
                    _monthCell(),
                    _sep(),
                    _dayCell(),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel',
                            style: TextStyle(color: View_C.inkSoft)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, ''),
                        child: const Text('Reset',
                            style: TextStyle(color: View_C.inkSoft)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _year == null
                            ? null
                            : () => Navigator.pop(context, _compose()),
                        style: TextButton.styleFrom(
                          foregroundColor: _ink,
                          disabledForegroundColor:
                              View_C.inkSoft.withOpacity(0.4),
                        ),
                        child: const Text('Done',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _compose() {
    if (_year == null) return '';
    final y = _year!.toString().padLeft(4, '0');
    if (_month == null) return y;
    final m = _month!.toString().padLeft(2, '0');
    if (_day == null) return '$y-$m';
    final d = _day!.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  TextStyle _cellStyle(bool filled) => TextStyle(
      color: filled ? View_C.ink : View_C.inkSoft,
      fontSize: 18,
      fontWeight: FontWeight.w600);

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('-',
            style: TextStyle(color: View_C.inkSoft, fontSize: 18)),
      );

  Widget _cell({
    required Widget child,
    required VoidCallback? onTap,
    required bool active,
    double width = 88,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: active ? 120 : 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _cellBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? _ink : _ink.withOpacity(0.25),
            width: active ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _monthCell() {
    final enabled = _year != null;
    if (_active == _Active.month) {
      return _cell(
        active: true,
        onTap: null,
        child: _wheel(
          count: 13,
          initial: _month ?? 0,
          label: (i) => i == 0 ? 'None' : '$i',
          onSelected: (i) {
            setState(() {
              _month = i == 0 ? null : i;
              if (_month == null) _day = null;
              if (_month != null && _day != null) {
                final dim = _daysInMonth(_year ?? 2000, _month!);
                if (_day! > dim) _day = dim;
              }
            });
          },
        ),
      );
    }
    return _cell(
      active: false,
      onTap: enabled ? () => setState(() => _active = _Active.month) : null,
      child: Text(
        _month == null ? '____' : _months[_month! - 1],
        style: _month == null
            ? TextStyle(
                color: enabled
                    ? View_C.inkSoft
                    : View_C.inkSoft.withOpacity(0.4),
                fontSize: 18,
                fontWeight: FontWeight.w600)
            : _cellStyle(true),
      ),
    );
  }

  Widget _dayCell() {
    final enabled = _year != null && _month != null;
    final dim = (_year != null && _month != null)
        ? _daysInMonth(_year!, _month!)
        : 31;
    if (_active == _Active.day) {
      return _cell(
        active: true,
        onTap: null,
        child: _wheel(
          count: dim + 1,
          initial: _day ?? 0,
          label: (i) => i == 0 ? 'None' : '$i',
          onSelected: (i) {
            setState(() => _day = i == 0 ? null : i);
          },
        ),
      );
    }
    return _cell(
      active: false,
      onTap: enabled ? () => setState(() => _active = _Active.day) : null,
      child: Text(
        _day == null ? '____' : '$_day',
        style: _day == null
            ? TextStyle(
                color: enabled
                    ? View_C.inkSoft
                    : View_C.inkSoft.withOpacity(0.4),
                fontSize: 18,
                fontWeight: FontWeight.w600)
            : _cellStyle(true),
      ),
    );
  }

  Widget _wheel({
    required int count,
    required int initial,
    required String Function(int) label,
    required ValueChanged<int> onSelected,
  }) {
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: initial),
      itemExtent: 28,
      diameterRatio: 1.1,
      squeeze: 1.0,
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
        background: _ink.withOpacity(0.08),
      ),
      onSelectedItemChanged: onSelected,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(label(i),
                style: const TextStyle(color: View_C.ink, fontSize: 16)),
          ),
      ],
    );
  }
}

/// 年份输入：失焦即保存（点别处收键盘自动提交），点外侧未输入则关闭。
class _YearInput extends StatefulWidget {
  final int colorIdx;
  final int? initial;
  const _YearInput({required this.colorIdx, this.initial});
  @override
  State<_YearInput> createState() => _YearInputState();
}

class _YearInputState extends State<_YearInput>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial?.toString() ?? '');
  final FocusNode _focus = FocusNode();
  bool _closed = false;
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  // 校验：空 → 关闭不改；合法 → 关闭并保存；非法 → 面板抖两下 + 清空 + 保持键盘
  void _validateOrReject() {
    if (_closed || !mounted) return;
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      _closed = true;
      Navigator.of(context).pop(); // 没输入，关闭不改
      return;
    }
    final y = int.tryParse(raw);
    if (y != null && y >= 1878 && y <= 2099) {
      _closed = true;
      Navigator.of(context).pop(y); // 合法，保存关闭
    } else {
      // 非法：面板抖两下 + 清空，键盘保持，等重输
      _shake.forward(from: 0);
      _ctrl.clear();
      FocusScope.of(context).requestFocus(_focus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = Style_C.ink(widget.colorIdx);
    final bg = Color.alphaBlend(
        Style_C.bg(widget.colorIdx).withOpacity(0.5), View_C.surface);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _validateOrReject,
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                // 抖两下：两个完整正弦周期，幅度随时间衰减
                final t = _shake.value;
                final dx = t == 0 ? 0.0 : sin(t * pi * 4) * 10 * (1 - t);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Year',
                          style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        cursorColor: ink,
                        style: const TextStyle(
                            color: View_C.ink, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '1878 – 2099',
                          hintStyle: const TextStyle(color: View_C.inkSoft),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: ink.withOpacity(0.25)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: ink),
                          ),
                        ),
                        onSubmitted: (_) => _validateOrReject(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
        ),
      ],
    );
  }
}