import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/light_config.dart';
import '../services/depth_service.dart';
import '../services/lighting_service.dart';

// 顶层数据类：传入 background isolate 的参数
class _LightingPayload {
  final img.Image sourceImage;
  final DepthResult depthResult;
  final LightingConfig config;
  final int? maxSize;

  const _LightingPayload({
    required this.sourceImage,
    required this.depthResult,
    required this.config,
    this.maxSize,
  });
}

// 顶层函数：在 background isolate 里执行光照计算 + PNG 编码
Future<Uint8List> _runLighting(_LightingPayload p) async {
  final lit = await LightingService.applyLighting(
    sourceImage: p.sourceImage,
    depthResult: p.depthResult,
    config: p.config,
    maxSize: p.maxSize,
  );
  return Uint8List.fromList(img.encodePng(lit));
}

enum AppState { idle, loadingModel, processing, done, error }

class AppProvider extends ChangeNotifier {
  final DepthService _depthService = DepthService();

  AppState _state = AppState.idle;
  String _statusMessage = '请选择一张人像图片';
  String? _errorMessage;

  img.Image? _sourceImage;
  DepthResult? _depthResult;
  Uint8List? _litImageBytes; // PNG bytes，用于 Image.memory 显示

  LightingConfig _config = LightingConfig();
  bool _showDepthMap = false;
  bool _modelLoaded = false;
  int _selectedLightIndex = 0;

  bool _isDragging = false;
  bool _isRendering = false;
  bool _renderPending = false;

  // ── Getters ──────────────────────────────────────────────────────────────
  AppState get state => _state;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  img.Image? get sourceImage => _sourceImage;
  DepthResult? get depthResult => _depthResult;
  Uint8List? get litImageBytes => _litImageBytes;
  LightingConfig get config => _config;
  bool get showDepthMap => _showDepthMap;
  bool get modelLoaded => _modelLoaded;
  bool get hasResult => _litImageBytes != null;
  int get selectedLightIndex => _selectedLightIndex;

  // ── 初始化模型 ────────────────────────────────────────────────────────────
  Future<void> initModel() async {
    if (_modelLoaded) return;
    _setState(AppState.loadingModel, '正在加载 MiDaS 模型…');
    await _depthService.initialize();
    if (_depthService.isInitialized) {
      _modelLoaded = true;
      _setState(AppState.idle, '模型加载成功，请选择图片');
    } else {
      _setState(AppState.error, '模型加载失败');
      _errorMessage = '未找到模型文件，请将 midas_small_256.tflite 放入 assets/models/';
    }
    notifyListeners();
  }

  // ── 加载图像并执行完整处理流程 ─────────────────────────────────────────────
  Future<void> processImage(img.Image image) async {
    _sourceImage = image;
    _litImageBytes = null;
    _depthResult = null;

    // Step 1: 深度估计
    _setState(AppState.processing, '正在进行深度估计…');
    final depthResult = await _depthService.estimateDepth(image);
    if (depthResult == null) {
      _setState(AppState.error, '深度估计失败');
      return;
    }
    _depthResult = depthResult;

    // Step 2: 打光
    await _applyLighting();
  }

  // ── 拖拽状态管理 ─────────────────────────────────────────────────────────
  void startDragging() {
    _isDragging = true;
  }

  void stopDragging() {
    _isDragging = false;
    // 松手后触发全分辨率渲染
    _applyLighting(preview: false);
  }

  // ── 仅重新打光（调节参数时调用）─────────────────────────────────────────────
  Future<void> relightOnly() async {
    if (_sourceImage == null || _depthResult == null) return;
    await _applyLighting(preview: _isDragging);
  }

  static const int _previewSize = 512;

  Future<void> _applyLighting({bool preview = false}) async {
    if (_sourceImage == null || _depthResult == null) return;

    // 节流：如果正在渲染，标记待处理，等当前渲染完后自动重跑
    if (_isRendering) {
      _renderPending = true;
      return;
    }
    _isRendering = true;

    if (!preview) {
      _setState(AppState.processing, '正在渲染光照…');
    }

    // 在后台 isolate 执行光照计算 + PNG 编码，不阻塞 UI 线程
    _litImageBytes = await compute(
      _runLighting,
      _LightingPayload(
        sourceImage: _sourceImage!,
        depthResult: _depthResult!,
        config: _config,
        maxSize: preview ? _previewSize : null,
      ),
    );
    _isRendering = false;

    // 如果拖拽期间有新请求排队，用最新参数再跑一次
    if (_renderPending) {
      _renderPending = false;
      _applyLighting(preview: _isDragging);
    } else {
      _setState(AppState.done, '完成（深度推理 ${_depthResult!.inferenceMs}ms）');
    }
  }

  // ── 光照参数更新 ──────────────────────────────────────────────────────────
  void updateConfig(LightingConfig newConfig) {
    _config = newConfig;
    notifyListeners();
    relightOnly();
  }

  void updateLight(int index, LightSource light) {
    final newLights = List<LightSource>.from(_config.lights);
    newLights[index] = light;
    updateConfig(_config.copyWith(lights: newLights));
  }

  void addLight() {
    if (_config.lights.length >= 3) return;
    final newLights = List<LightSource>.from(_config.lights)
      ..add(LightSource(x: 0.3, y: -0.3, z: 1.0));
    updateConfig(_config.copyWith(lights: newLights));
  }

  void removeLight(int index) {
    if (_config.lights.length <= 1) return;
    final newLights = List<LightSource>.from(_config.lights)..removeAt(index);
    if (_selectedLightIndex >= newLights.length) {
      _selectedLightIndex = newLights.length - 1;
    }
    updateConfig(_config.copyWith(lights: newLights));
  }

  void selectLight(int index) {
    if (index < 0 || index >= _config.lights.length) return;
    _selectedLightIndex = index;
    notifyListeners();
  }

  void toggleDepthMap() {
    _showDepthMap = !_showDepthMap;
    notifyListeners();
  }

  // ── 获取当前要显示的图像（打光结果 or 深度图）─────────────────────────────
  Uint8List? get displayImageBytes {
    if (_showDepthMap && _depthResult != null) {
      final depthImg = LightingService.depthToImage(_depthResult!);
      return Uint8List.fromList(img.encodePng(depthImg));
    }
    return _litImageBytes;
  }

  void _setState(AppState state, String message) {
    _state = state;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _depthService.dispose();
    super.dispose();
  }
}
