import 'package:flutter/material.dart';

/// 颜色选择器页面 — 预设色板 + HSB 微调
class ColorPickerPage extends StatefulWidget {
  final Color initialColor;
  const ColorPickerPage({super.key, required this.initialColor});

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  late HSVColor _hsv;

  // 预设颜色
  static const _presets = [
    Color(0xFFFFFFFF), // 白
    Color(0xFFFFD580), // 暖黄
    Color(0xFFFFAA55), // 橙
    Color(0xFFFF6666), // 红
    Color(0xFFFF66B2), // 粉
    Color(0xFFCC66FF), // 紫
    Color(0xFF6699FF), // 蓝
    Color(0xFF66CCFF), // 天蓝
    Color(0xFF66FFCC), // 青
    Color(0xFF88FF66), // 绿
    Color(0xFFCCFF66), // 黄绿
    Color(0xFFFFFF66), // 黄
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _hsv.toColor();

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        title: const Text('选择颜色'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, currentColor),
            child: const Text('确定', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── 当前颜色预览 ──────────────────────────────────────
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: currentColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 预设色板 ──────────────────────────────────────────
            _buildPresetGrid(),
            const SizedBox(height: 28),

            // ── HSB 滑块 ──────────────────────────────────────────
            _buildHueSlider(),
            const SizedBox(height: 16),
            _buildSatBrightPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _presets.map((c) {
        final selected = _colorClose(c, _hsv.toColor());
        return GestureDetector(
          onTap: () => setState(() => _hsv = HSVColor.fromColor(c)),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: Colors.white, width: 3)
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.2), width: 1),
              boxShadow: selected
                  ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHueSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hue', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return GestureDetector(
              onPanDown: (d) => _updateHue(d.localPosition.dx, w),
              onPanUpdate: (d) => _updateHue(d.localPosition.dx, w),
              child: CustomPaint(
                size: Size(w, 36),
                painter: _HueBarPainter(hue: _hsv.hue),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _updateHue(double dx, double width) {
    final hue = (dx / width).clamp(0.0, 1.0) * 360.0;
    setState(() => _hsv = _hsv.withHue(hue));
  }

  Widget _buildSatBrightPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Saturation & Brightness',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1.6,
          child: LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return GestureDetector(
              onPanDown: (d) => _updateSB(d.localPosition, w, h),
              onPanUpdate: (d) => _updateSB(d.localPosition, w, h),
              child: CustomPaint(
                size: Size(w, h),
                painter:
                    _SatBrightPainter(hue: _hsv.hue, sat: _hsv.saturation, val: _hsv.value),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _updateSB(Offset pos, double w, double h) {
    final s = (pos.dx / w).clamp(0.0, 1.0);
    final v = 1.0 - (pos.dy / h).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  bool _colorClose(Color a, Color b) {
    return ((a.r - b.r) * 255).abs() < 8 &&
        ((a.g - b.g) * 255).abs() < 8 &&
        ((a.b - b.b) * 255).abs() < 8;
  }
}

// ── Hue 渐变条 Painter ─────────────────────────────────────────────────────

class _HueBarPainter extends CustomPainter {
  final double hue;
  _HueBarPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.clipRRect(rect);

    // 画色相渐变
    final colors = List.generate(
        7, (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor());
    final gradient = LinearGradient(colors: colors);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = gradient.createShader(Offset.zero & size),
    );

    // 指示器
    final x = (hue / 360.0) * size.width;
    canvas.drawCircle(
      Offset(x.clamp(8, size.width - 8), size.height / 2),
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(x.clamp(8, size.width - 8), size.height / 2),
      10,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => hue != old.hue;
}

// ── Saturation-Brightness 二维选择器 Painter ────────────────────────────────

class _SatBrightPainter extends CustomPainter {
  final double hue, sat, val;
  _SatBrightPainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.clipRRect(rect);

    // 底色：纯色相
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
    // 横向白→透明渐变（饱和度）
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(Offset.zero & size),
    );
    // 纵向透明→黑渐变（亮度）
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(Offset.zero & size),
    );

    // 指示器
    final x = sat * size.width;
    final y = (1 - val) * size.height;
    canvas.drawCircle(
      Offset(x, y),
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(x, y),
      12,
      Paint()..color = HSVColor.fromAHSV(1, hue, sat, val).toColor(),
    );
  }

  @override
  bool shouldRepaint(_SatBrightPainter old) =>
      hue != old.hue || sat != old.sat || val != old.val;
}
