import 'package:flutter/material.dart';
import '../theme.dart';
import '../smb/smb_client.dart';

const _textExt = {
  'txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml',
  'ini', 'conf', 'cfg', 'srt', 'vtt', 'ass', 'nfo', 'tsv'
};

bool isTextFile(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0) return false;
  return _textExt.contains(name.substring(i + 1).toLowerCase());
}

/// 纯文本只读查看页（UTF-8、原样显示、可滚动可选中）
class TextPage extends StatefulWidget {
  final SmbCreds creds;
  final String filePath; // 相对 share 根的完整路径
  final String fileName;
  const TextPage({
    super.key,
    required this.creds,
    required this.filePath,
    required this.fileName,
  });
  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  bool _loading = true;
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await SmbClient.readFile(widget.creds, widget.filePath);
      if (!mounted) return;
      setState(() {
        _content = text ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: C.ink, size: 20),
        ),
        title: Text(widget.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: C.ink, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Failed to read:\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.inkSoft)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  child: SelectableText(
                    _content!.isEmpty ? '(empty file)' : _content!,
                    style: const TextStyle(
                      color: C.ink,
                      fontSize: 13,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
    );
  }
}