import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;

/// MiDaS 深度估计服务（ONNX Runtime 版）
/// 模型：midas_small_256.onnx
/// 输入：[1, 3, 256, 256] float32，NCHW，ImageNet 归一化
/// 输出：[1, 256, 256] float32，相对深度值
class DepthService {
  static const String _modelPath = 'assets/models/midas_small_256.onnx';
  static const int _inputSize = 256;

  // ImageNet 均值和标准差（MiDaS 官方预处理）
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std  = [0.229, 0.224, 0.225];

  OrtSession? _session;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    try {
      OrtEnv.instance.init();

      // 从 assets 加载模型字节
      final rawAsset = await rootBundle.load(_modelPath);
      final modelBytes = rawAsset.buffer.asUint8List();

      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(modelBytes, options);

      _initialized = true;
      debugPrint('DepthService: ONNX 模型加载成功');
      debugPrint('  输入: ${_session!.inputNames}');
      debugPrint('  输出: ${_session!.outputNames}');
    } catch (e) {
      debugPrint('DepthService: 模型加载失败 - $e');
      _initialized = false;
    }
  }

  /// 对图像执行深度估计，返回归一化深度图（值域 [0,1]）
  Future<DepthResult?> estimateDepth(img.Image image) async {
    if (!_initialized || _session == null) {
      debugPrint('DepthService: 未初始化，跳过推理');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    // 1. 缩放到 256×256
    final resized = img.copyResize(
      image,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // 2. 转 NCHW float32，并应用 ImageNet 归一化
    // MiDaS ONNX 输入 shape: [1, 3, 256, 256]（通道优先）
    final inputData = Float32List(_inputSize * _inputSize * 3);
    const planeSize = _inputSize * _inputSize;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final offset = y * _inputSize + x;
        inputData[offset]                = (pixel.r / 255.0 - _mean[0]) / _std[0];
        inputData[planeSize + offset]    = (pixel.g / 255.0 - _mean[1]) / _std[1];
        inputData[2 * planeSize + offset] = (pixel.b / 255.0 - _mean[2]) / _std[2];
      }
    }

    // 3. 构建输入 tensor [1, 3, 256, 256]
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, _inputSize, _inputSize],
    );
    final inputs = {_session!.inputNames[0]: inputTensor};

    // 4. 同步推理（在 compute isolate 外调用，避免阻塞 UI）
    final runOptions = OrtRunOptions();
    final outputs = _session!.run(runOptions, inputs);
    inputTensor.release();
    runOptions.release();

    stopwatch.stop();
    debugPrint('DepthService: 推理耗时 ${stopwatch.elapsedMilliseconds}ms');

    if (outputs.isEmpty || outputs[0] == null) {
      debugPrint('DepthService: 输出为空');
      return null;
    }

    // 5. 提取输出并展平为 Float32List
    final rawOutput = outputs[0]!.value;
    outputs[0]!.release();

    if (rawOutput == null) return null;
    final flat = _flattenToFloat32(rawOutput as List, _inputSize * _inputSize);

    // 6. 归一化到 [0, 1]
    final normalized = _normalize(flat);

    return DepthResult(
      depthMap: normalized,
      width: _inputSize,
      height: _inputSize,
      originalWidth: image.width,
      originalHeight: image.height,
      inferenceMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// 将 ONNX 输出的嵌套 List 展平为 Float32List
  Float32List _flattenToFloat32(List data, int expectedSize) {
    final result = Float32List(expectedSize);
    int idx = 0;
    void flatten(dynamic obj) {
      if (obj is List) {
        for (final item in obj) {
          flatten(item);
        }
      } else if (idx < expectedSize) {
        result[idx++] = (obj as num).toDouble();
      }
    }
    flatten(data);
    return result;
  }

  Float32List _normalize(Float32List data) {
    double minVal = data[0], maxVal = data[0];
    for (final v in data) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final range = maxVal - minVal;
    if (range < 1e-6) return Float32List(data.length);
    final result = Float32List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = (data[i] - minVal) / range;
    }
    return result;
  }

  void dispose() {
    _session?.release();
    OrtEnv.instance.release();
    _initialized = false;
  }
}

/// 深度估计结果
class DepthResult {
  /// 归一化深度图，长度 = width × height，值域 [0,1]
  final Float32List depthMap;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final int inferenceMs;

  const DepthResult({
    required this.depthMap,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.inferenceMs,
  });
}
