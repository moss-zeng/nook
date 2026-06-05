import 'package:flutter/material.dart';
import 'theme.dart';

/// 通用文本输入弹窗：
/// - 面板底色 = 作品/人物色号混合（视觉统一）
/// - 输入框与面板融为一体（无独立色块）
/// - 失焦即保存：点面板内别处收起键盘并提交（不必按键盘 ✔）
/// - 点面板外侧：仍在输入则先收键盘（不关闭），否则关闭
///
/// 返回用户提交的文本；点 Cancel / 外侧关闭返回 null。
Future<String?> showColoredInput(
  BuildContext context, {
  required int colorIdx,
  required String title,
  String initial = '',
  String hint = '',
  int maxLines = 1,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.35),
    barrierDismissible: false, // 自己处理外侧点击（输入时先收键盘）
    builder: (_) => _ColoredInputDialog(
      colorIdx: colorIdx,
      title: title,
      initial: initial,
      hint: hint,
      maxLines: maxLines,
      keyboardType: keyboardType,
    ),
  );
}

class _ColoredInputDialog extends StatefulWidget {
  final int colorIdx;
  final String title;
  final String initial;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  const _ColoredInputDialog({
    required this.colorIdx,
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLines,
    this.keyboardType,
  });
  @override
  State<_ColoredInputDialog> createState() => _ColoredInputDialogState();
}

class _ColoredInputDialogState extends State<_ColoredInputDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();
  bool _closed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // 关闭并保存当前文本（点外侧、键盘已落时调用）。直接 pop，不延后、不靠失焦。
  void _closeWithSave() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.alphaBlend(
        Style_C.bg(widget.colorIdx).withOpacity(0.5), View_C.surface);
    final ink = Style_C.ink(widget.colorIdx);

    return Stack(
      children: [
        // 点外侧：直接关闭并保存当前文本（输完即走，不留空面板）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeWithSave,
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                // 点面板内部空白：仅收起键盘（不关闭）
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      // 输入框：与面板融为一体（无独立填充色块）
                      TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        maxLines: widget.maxLines,
                        minLines: 1,
                        keyboardType: widget.keyboardType,
                        cursorColor: ink,
                        style: const TextStyle(
                            color: View_C.ink, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          hintStyle: const TextStyle(color: View_C.inkSoft),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: ink.withOpacity(0.25)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: ink),
                          ),
                        ),
                        onSubmitted: widget.maxLines == 1
                            ? (_) => _closeWithSave()
                            : null,
                      ),
                    ],
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