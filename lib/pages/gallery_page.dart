import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';
import '../smb/smb_client.dart';

const _imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'avif'};

bool isImageFile(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0) return false;
  return _imageExt.contains(name.substring(i + 1).toLowerCase());
}

/// 列出某人物 .gallery/ 下的图片（不递归）。返回文件名列表。
Future<List<String>> listGalleryImages(SmbCreds c, String personPath) async {
  try {
    final entries = await SmbClient.list(c, '$personPath/.gallery');
    final imgs = entries
        .where((e) => !e.isDir && isImageFile(e.name))
        .map((e) => e.name)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return imgs;
  } catch (_) {
    return [];
  }
}

/// 图片库网格页（类似第二层瀑布流，纯图无名）
class GalleryPage extends StatelessWidget {
  final SmbCreds creds;
  final String personPath; // 人物路径（相对 share 根）
  final String personName;
  final List<String> images; // 文件名（已确认非空）
  const GalleryPage({
    super.key,
    required this.creds,
    required this.personPath,
    required this.personName,
    required this.images,
  });

  String get _galleryDir => '$personPath/.gallery';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: View_C.bg,
      appBar: AppBar(
        backgroundColor: View_C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: View_C.ink, size: 20),
        ),
        title: Text(personName,
            style: const TextStyle(
                color: View_C.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
        ),
        itemCount: images.length,
        itemBuilder: (_, i) {
          final name = images[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              opaque: false,
              barrierColor: Colors.black.withOpacity(0.85),
              pageBuilder: (_, __, ___) => _GalleryViewer(
                creds: creds,
                galleryDir: _galleryDir,
                images: images,
                initialIndex: i,
              ),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CoverImage(
                creds: creds,
                candidates: ['$_galleryDir/$name'],
                fallbackName: '',
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 全屏查看：半透明黑底 + 文件名 + 双指缩放/拖拽 + 左右滑切换
class _GalleryViewer extends StatefulWidget {
  final SmbCreds creds;
  final String galleryDir;
  final List<String> images;
  final int initialIndex;
  const _GalleryViewer({
    required this.creds,
    required this.galleryDir,
    required this.images,
    required this.initialIndex,
  });
  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _pc =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  String get _currentName => widget.images[_index];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox.expand(),
            ),
          ),
          PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.images.length,
            itemBuilder: (_, i) {
              final name = widget.images[i];
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Center(
                  child: CoverImage(
                    creds: widget.creds,
                    candidates: ['${widget.galleryDir}/$name'],
                    fallbackName: '',
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 22),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _currentName,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 公开入口：在 App 内打开图片查看器（普通模式点图片复用）
void openImageViewer(
  BuildContext context,
  SmbCreds creds,
  String dir,
  List<String> images,
  int index,
) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black.withOpacity(0.85),
    pageBuilder: (_, __, ___) => _GalleryViewer(
      creds: creds,
      galleryDir: dir,
      images: images,
      initialIndex: index,
    ),
  ));
}