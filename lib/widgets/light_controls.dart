import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/light_config.dart';
import '../providers/app_provider.dart';
import 'color_picker_page.dart';

/// 底部光照控制栏：颜色圆圈 + Intensity 滑块 + Distance 滑块
class LightControlBar extends StatelessWidget {
  const LightControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    if (!provider.hasResult) return const SizedBox.shrink();

    final idx = provider.selectedLightIndex;
    final light = provider.config.lights[idx];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          // ── 颜色圆圈（点击打开颜色选择器）──────────────────────
          GestureDetector(
            onTap: () => _openColorPicker(context, provider, idx, light),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: light.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: light.color.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                    color: _isDark(light.color) ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // ── 滑块区域 ──────────────────────────────────────────
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CompactSlider(
                  label: 'Intensity',
                  value: light.intensity,
                  min: 0.0,
                  max: 2.0,
                  activeColor: light.color,
                  onChanged: (v) => provider.updateLight(
                      idx, light.copyWith(intensity: v)),
                ),
                const SizedBox(height: 4),
                _CompactSlider(
                  label: 'Distance',
                  value: light.z,
                  min: -5.0,
                  max: 5.0,
                  activeColor: Colors.white70,
                  onChanged: (v) =>
                      provider.updateLight(idx, light.copyWith(z: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openColorPicker(
    BuildContext context,
    AppProvider provider,
    int idx,
    LightSource light,
  ) async {
    final picked = await Navigator.of(context).push<Color>(
      MaterialPageRoute(
        builder: (_) => ColorPickerPage(initialColor: light.color),
      ),
    );
    if (picked != null) {
      provider.updateLight(idx, light.copyWith(color: picked));
    }
  }

  bool _isDark(Color c) =>
      (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) < 0.5;
}

// ── 紧凑滑块行 ──────────────────────────────────────────────────────────────

class _CompactSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _CompactSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: activeColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
