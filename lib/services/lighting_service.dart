import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/light_config.dart';
import 'depth_service.dart';

/// 打光服务
/// 流程：深度图 → 法线图 → Phong 光照模型 → 输出图像
class LightingService {
  /// 主入口：根据原始图像、深度结果和光照配置生成打光图像
  /// [maxSize] 不为 null 时，输出限制在该尺寸内（用于拖拽预览）
  static Future<img.Image> applyLighting({
    required img.Image sourceImage,
    required DepthResult depthResult,
    required LightingConfig config,
    int? maxSize,
  }) async {
    final dw = depthResult.width;
    final dh = depthResult.height;

    // 确定输出尺寸：有 maxSize 时缩小，否则用原始尺寸
    final srcW = sourceImage.width;
    final srcH = sourceImage.height;
    final img.Image src;
    final int ow, oh;
    if (maxSize != null && (srcW > maxSize || srcH > maxSize)) {
      final scale = maxSize / max(srcW, srcH);
      ow = (srcW * scale).round();
      oh = (srcH * scale).round();
      src = img.copyResize(sourceImage, width: ow, height: oh,
          interpolation: img.Interpolation.linear);
    } else {
      ow = srcW;
      oh = srcH;
      src = sourceImage;
    }

    // 1. 在深度图分辨率上计算法线
    final normals = _computeNormals(depthResult.depthMap, dw, dh, config.depthScale);

    // 2. 逐像素计算光照（法线通过双线性插值采样）
    final output = img.Image(width: ow, height: oh);

    // 环境光（提到循环外，只算一次）
    final ar = config.ambientColor.r * config.ambientIntensity;
    final ag = config.ambientColor.g * config.ambientIntensity;
    final ab = config.ambientColor.b * config.ambientIntensity;

    // 预计算启用的光源属性
    final enabledLights = config.lights.where((l) => l.enabled).toList();

    for (int y = 0; y < oh; y++) {
      // 当前像素在法线图中的浮点坐标
      final ny0 = y / oh * dh;
      for (int x = 0; x < ow; x++) {
        final nx0 = x / ow * dw;

        // 双线性插值采样法线
        final nx = _sampleNormal(normals, dw, dh, nx0, ny0, 0);
        final ny = _sampleNormal(normals, dw, dh, nx0, ny0, 1);
        final nz = _sampleNormal(normals, dw, dh, nx0, ny0, 2);

        // 视线方向（假设从正面看）
        const vx = 0.0, vy = 0.0, vz = 1.0;

        double totalR = ar, totalG = ag, totalB = ab;

        // 像素的 NDC 坐标（用原始分辨率计算）
        final px = (x / ow) * 2.0 - 1.0;
        final py = (y / oh) * 2.0 - 1.0;

        for (final light in enabledLights) {
          double lx, ly, lz;
          if (light.type == LightType.directional) {
            lx = light.x;
            ly = light.y;
            lz = light.z;
          } else {
            lx = light.x - px;
            ly = light.y - py;
            lz = light.z;
          }
          final lLen = sqrt(lx * lx + ly * ly + lz * lz);
          if (lLen < 1e-6) continue;
          lx /= lLen; ly /= lLen; lz /= lLen;

          final lr = light.color.r * light.intensity;
          final lg = light.color.g * light.intensity;
          final lb = light.color.b * light.intensity;

          // 漫反射：kd * max(N·L, 0)
          final ndl = max(0.0, nx * lx + ny * ly + nz * lz);
          final diffuse = ndl * config.diffuseStrength;
          totalR += lr * diffuse;
          totalG += lg * diffuse;
          totalB += lb * diffuse;

          // 镜面反射（Blinn-Phong 半程向量）
          final hx = lx + vx, hy = ly + vy, hz = lz + vz;
          final hLen = sqrt(hx * hx + hy * hy + hz * hz);
          if (hLen > 1e-6) {
            final ndh = max(0.0, nx * (hx / hLen) + ny * (hy / hLen) + nz * (hz / hLen));
            final specular = pow(ndh, config.shininess).toDouble() * config.specularStrength;
            totalR += lr * specular;
            totalG += lg * specular;
            totalB += lb * specular;
          }
        }

        // 原始像素颜色
        final srcPixel = src.getPixel(x, y);
        final sr = srcPixel.r / 255.0;
        final sg = srcPixel.g / 255.0;
        final sb = srcPixel.b / 255.0;

        final fr = _clamp01(sr * totalR);
        final fg = _clamp01(sg * totalG);
        final fb = _clamp01(sb * totalB);

        output.setPixelRgb(x, y, (fr * 255).round(), (fg * 255).round(), (fb * 255).round());
      }
    }

    return output;
  }

  /// 双线性插值采样法线图的某个分量
  /// [channel]: 0=nx, 1=ny, 2=nz
  static double _sampleNormal(
    Float32List normals, int w, int h,
    double fx, double fy, int channel,
  ) {
    final x0 = fx.floor().clamp(0, w - 1);
    final y0 = fy.floor().clamp(0, h - 1);
    final x1 = (x0 + 1).clamp(0, w - 1);
    final y1 = (y0 + 1).clamp(0, h - 1);
    final dx = fx - x0;
    final dy = fy - y0;

    final v00 = normals[(y0 * w + x0) * 3 + channel];
    final v10 = normals[(y0 * w + x1) * 3 + channel];
    final v01 = normals[(y1 * w + x0) * 3 + channel];
    final v11 = normals[(y1 * w + x1) * 3 + channel];

    return v00 * (1 - dx) * (1 - dy) +
           v10 * dx * (1 - dy) +
           v01 * (1 - dx) * dy +
           v11 * dx * dy;
  }

  /// 从深度图计算每像素法线（Sobel 3×3 梯度）
  /// 返回 Float32List，每像素 3 个 float (nx, ny, nz)，已归一化
  static Float32List _computeNormals(
    Float32List depthMap,
    int width,
    int height,
    double depthScale,
  ) {
    final normals = Float32List(width * height * 3);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 3;

        // Sobel x 方向梯度
        final dzdx = _sobelX(depthMap, x, y, width, height) * depthScale;
        // Sobel y 方向梯度
        final dzdy = _sobelY(depthMap, x, y, width, height) * depthScale;

        // 法线 = normalize(-dzdx, -dzdy, 1)
        final nx = -dzdx;
        final ny = -dzdy;
        const nz = 1.0;
        final len = sqrt(nx * nx + ny * ny + nz * nz);

        normals[idx]     = nx / len;
        normals[idx + 1] = ny / len;
        normals[idx + 2] = nz / len;
      }
    }
    return normals;
  }

  static double _sobelX(Float32List d, int x, int y, int w, int h) {
    final x0 = (x - 1).clamp(0, w - 1);
    final x2 = (x + 1).clamp(0, w - 1);
    final y0 = (y - 1).clamp(0, h - 1);
    final y1 = y;
    final y2 = (y + 1).clamp(0, h - 1);
    return (
      -d[y0 * w + x0] - 2 * d[y1 * w + x0] - d[y2 * w + x0] +
       d[y0 * w + x2] + 2 * d[y1 * w + x2] + d[y2 * w + x2]
    ) / 8.0;
  }

  static double _sobelY(Float32List d, int x, int y, int w, int h) {
    final x0 = (x - 1).clamp(0, w - 1);
    final x1 = x;
    final x2 = (x + 1).clamp(0, w - 1);
    final y0 = (y - 1).clamp(0, h - 1);
    final y2 = (y + 1).clamp(0, h - 1);
    return (
      -d[y0 * w + x0] - 2 * d[y0 * w + x1] - d[y0 * w + x2] +
       d[y2 * w + x0] + 2 * d[y2 * w + x1] + d[y2 * w + x2]
    ) / 8.0;
  }

  /// 将深度图渲染为可视化灰度图像（用于调试）
  static img.Image depthToImage(DepthResult depthResult) {
    final w = depthResult.width;
    final h = depthResult.height;
    final output = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = (depthResult.depthMap[y * w + x] * 255).round().clamp(0, 255);
        output.setPixelRgb(x, y, v, v, v);
      }
    }
    return output;
  }

  static double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}
