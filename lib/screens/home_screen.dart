import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/light_config.dart';
import '../providers/app_provider.dart';
import '../widgets/light_controls.dart';

// 顶层函数：在 background isolate 里解码并缩放图片
img.Image? _decodeAndResize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  const maxDim = 1080;
  final larger = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (larger > maxDim) {
    final scale = maxDim / larger;
    return img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return decoded;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部栏 ──────────────────────────────────────────────
            const _TopBar(),
            // ── 图像预览区域 ────────────────────────────────────────
            const Expanded(child: _ImageArea()),
            // ── 底部控件 ────────────────────────────────────────────
            const LightControlBar(),
            const _BottomToolbar(),
          ],
        ),
      ),
    );
  }
}

// ── 顶部栏 ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isProcessing = provider.state == AppState.processing ||
        provider.state == AppState.loadingModel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Text(
            'Portrait Light',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isProcessing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          if (provider.depthResult != null) ...[
            const SizedBox(width: 12),
            _DepthMapToggle(),
          ],
        ],
      ),
    );
  }
}

// ── 图像预览区域 ────────────────────────────────────────────────────────────

class _ImageArea extends StatefulWidget {
  const _ImageArea();

  @override
  State<_ImageArea> createState() => _ImageAreaState();
}

class _ImageAreaState extends State<_ImageArea> {
  int? _draggingLightIndex;

  Rect _computeImageRect(Size container, Size image) {
    final ca = container.width / container.height;
    final ia = image.width / image.height;
    double w, h;
    if (ia > ca) {
      w = container.width;
      h = container.width / ia;
    } else {
      h = container.height;
      w = container.height * ia;
    }
    return Rect.fromLTWH(
      (container.width - w) / 2,
      (container.height - h) / 2,
      w,
      h,
    );
  }

  Offset _ndcToScreen(double ndcX, double ndcY, Rect imageRect) {
    return Offset(
      (ndcX + 1.0) / 2.0 * imageRect.width + imageRect.left,
      (ndcY + 1.0) / 2.0 * imageRect.height + imageRect.top,
    );
  }

  (double, double) _screenToNdc(Offset pos, Rect imageRect) {
    final nx = ((pos.dx - imageRect.left) / imageRect.width) * 2.0 - 1.0;
    final ny = ((pos.dy - imageRect.top) / imageRect.height) * 2.0 - 1.0;
    return (nx.clamp(-1.5, 1.5), ny.clamp(-1.5, 1.5));
  }

  int? _hitLight(Offset pos, Rect imageRect, List<LightSource> lights) {
    const r = 22.0;
    for (int i = 0; i < lights.length; i++) {
      final s = _ndcToScreen(lights[i].x, lights[i].y, imageRect);
      if ((pos - s).distance <= r) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final displayBytes = provider.displayImageBytes;

    if (displayBytes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.portrait, size: 80, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              provider.statusMessage,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final container = Size(constraints.maxWidth, constraints.maxHeight);
      final src = provider.sourceImage;
      final imageSize = src != null
          ? Size(src.width.toDouble(), src.height.toDouble())
          : container;
      final imageRect = _computeImageRect(container, imageSize);
      final lights = provider.config.lights;
      final selectedIdx = provider.selectedLightIndex;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final hit = _hitLight(d.localPosition, imageRect, lights);
          if (hit != null) provider.selectLight(hit);
        },
        onTapUp: (d) {
          final hit = _hitLight(d.localPosition, imageRect, lights);
          if (hit == null) {
            final (nx, ny) = _screenToNdc(d.localPosition, imageRect);
            final light = lights[selectedIdx];
            provider.updateLight(selectedIdx, light.copyWith(x: nx, y: ny));
          }
        },
        onPanStart: (d) {
          final hit = _hitLight(d.localPosition, imageRect, lights);
          if (hit != null) {
            setState(() => _draggingLightIndex = hit);
            provider.selectLight(hit);
            provider.startDragging();
          }
        },
        onPanUpdate: (d) {
          final idx = _draggingLightIndex;
          if (idx == null) return;
          final (nx, ny) = _screenToNdc(d.localPosition, imageRect);
          provider.updateLight(
              idx, provider.config.lights[idx].copyWith(x: nx, y: ny));
        },
        onPanEnd: (_) {
          setState(() => _draggingLightIndex = null);
          provider.stopDragging();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(displayBytes, fit: BoxFit.contain, gaplessPlayback: true),
            CustomPaint(
              painter: _LightOverlayPainter(
                lights: lights,
                selectedIndex: selectedIdx,
                imageRect: imageRect,
                draggingIndex: _draggingLightIndex,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── 光源位置叠加层 ──────────────────────────────────────────────────────────

class _LightOverlayPainter extends CustomPainter {
  final List<LightSource> lights;
  final int selectedIndex;
  final Rect imageRect;
  final int? draggingIndex;

  const _LightOverlayPainter({
    required this.lights,
    required this.selectedIndex,
    required this.imageRect,
    this.draggingIndex,
  });

  Offset _ndcToScreen(double ndcX, double ndcY) => Offset(
        (ndcX + 1.0) / 2.0 * imageRect.width + imageRect.left,
        (ndcY + 1.0) / 2.0 * imageRect.height + imageRect.top,
      );

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < lights.length; i++) {
      final light = lights[i];
      if (!light.enabled) continue;

      final pos = _ndcToScreen(light.x, light.y);
      final isSelected = i == selectedIndex;
      final isDragging = i == draggingIndex;
      final radius = isDragging ? 14.0 : (isSelected ? 12.0 : 9.0);

      if (isSelected || isDragging) {
        canvas.drawCircle(
          pos,
          radius + 8,
          Paint()
            ..color = light.color.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          pos,
          radius + 5,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      canvas.drawCircle(
        pos,
        radius,
        Paint()..color = light.color.withValues(alpha: 0.88),
      );
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: _isDark(light.color) ? Colors.white : Colors.black87,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  bool _isDark(Color c) =>
      (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) < 0.5;

  @override
  bool shouldRepaint(_LightOverlayPainter old) =>
      lights != old.lights ||
      selectedIndex != old.selectedIndex ||
      imageRect != old.imageRect ||
      draggingIndex != old.draggingIndex;
}

// ── 深度图切换按钮 ──────────────────────────────────────────────────────────

class _DepthMapToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return GestureDetector(
      onTap: () => provider.toggleDepthMap(),
      child: Icon(
        provider.showDepthMap ? Icons.image : Icons.layers,
        color: provider.showDepthMap ? Colors.blueAccent : Colors.white70,
        size: 22,
      ),
    );
  }
}

// ── 底部工具栏（选择图片 / 保存 / 添加删除光源）─────────────────────────────

class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isProcessing = provider.state == AppState.processing ||
        provider.state == AppState.loadingModel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ToolbarButton(
            icon: Icons.photo_library_outlined,
            label: '选图',
            onTap: isProcessing ? null : () => _showImageSourceSheet(context),
          ),
          if (provider.hasResult)
            _ToolbarButton(
              icon: Icons.save_alt,
              label: '保存',
              onTap: isProcessing ? null : () => _saveResult(context),
            ),
          _ToolbarButton(
            icon: Icons.add_circle_outline,
            label: '加灯',
            onTap: provider.config.lights.length >= 3
                ? null
                : () => provider.addLight(),
          ),
          if (provider.config.lights.length > 1)
            _ToolbarButton(
              icon: Icons.remove_circle_outline,
              label: '删灯',
              onTap: () => provider.removeLight(provider.selectedLightIndex),
            ),
        ],
      ),
    );
  }

  void _showImageSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              title: const Text('拍照', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _captureAndProcess(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('从相册选择', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickAndProcess(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _captureAndProcess(BuildContext context) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    await _processBytes(context, bytes);
  }

  Future<void> _pickAndProcess(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    Uint8List? bytes = file.bytes;

    if (bytes == null && file.path != null && !kIsWeb) {
      bytes = await File(file.path!).readAsBytes();
    }

    if (bytes == null) {
      if (context.mounted) _showSnack(context, '无法读取图片文件');
      return;
    }

    await _processBytes(context, bytes);
  }

  Future<void> _processBytes(BuildContext context, Uint8List bytes) async {
    // 在后台 isolate 解码 + 缩放，不阻塞 UI 线程
    final source = await compute(_decodeAndResize, bytes);
    if (source == null) {
      if (context.mounted) _showSnack(context, '无法解码图像');
      return;
    }

    if (context.mounted) {
      await context.read<AppProvider>().processImage(source);
    }
  }

  Future<void> _saveResult(BuildContext context) async {
    final bytes = context.read<AppProvider>().litImageBytes;
    if (bytes == null) return;

    if (kIsWeb) {
      _showSnack(context, 'Web 端暂不支持保存');
      return;
    }

    try {
      // 写入临时文件，再通过 Gal 保存到相册
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tmpFile = File('${Directory.systemTemp.path}/portrait_light_$ts.png');
      await tmpFile.writeAsBytes(bytes);
      await Gal.putImage(tmpFile.path);
      await tmpFile.delete();
      if (context.mounted) _showSnack(context, '已保存到相册');
    } catch (e) {
      if (context.mounted) _showSnack(context, '保存失败: $e');
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
