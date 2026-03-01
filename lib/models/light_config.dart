import 'dart:ui';

/// 光源类型
enum LightType { point, directional }

/// 单个光源配置
class LightSource {
  /// 光源位置（NDC 坐标，范围 -1 到 1）
  double x;
  double y;

  /// 光源距离（-5 前方 ~ +5 后方）
  double z;

  /// 光源颜色
  Color color;

  /// 光源强度 0.0 ~ 2.0
  double intensity;

  /// 光源类型
  LightType type;

  /// 是否启用
  bool enabled;

  LightSource({
    this.x = 0.0,
    this.y = -0.5,
    this.z = 1.0,
    this.color = const Color(0xFFFFFFFF),
    this.intensity = 1.0,
    this.type = LightType.point,
    this.enabled = true,
  });

  LightSource copyWith({
    double? x,
    double? y,
    double? z,
    Color? color,
    double? intensity,
    LightType? type,
    bool? enabled,
  }) {
    return LightSource(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      color: color ?? this.color,
      intensity: intensity ?? this.intensity,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// 整体光照配置
class LightingConfig {
  /// 光源列表（最多支持 3 个）
  List<LightSource> lights;

  /// 环境光强度 0.0 ~ 1.0
  double ambientIntensity;

  /// 环境光颜色
  Color ambientColor;

  /// 漫反射系数 0.0 ~ 1.0
  double diffuseStrength;

  /// 镜面反射系数 0.0 ~ 1.0
  double specularStrength;

  /// 镜面反射光泽度（shininess）
  double shininess;

  /// 深度影响强度（法线计算权重）0.0 ~ 2.0
  double depthScale;

  LightingConfig({
    List<LightSource>? lights,
    this.ambientIntensity = 0.2,
    this.ambientColor = const Color(0xFFFFFFFF),
    this.diffuseStrength = 0.8,
    this.specularStrength = 0.3,
    this.shininess = 32.0,
    this.depthScale = 1.0,
  }) : lights = lights ?? [LightSource()];

  LightingConfig copyWith({
    List<LightSource>? lights,
    double? ambientIntensity,
    Color? ambientColor,
    double? diffuseStrength,
    double? specularStrength,
    double? shininess,
    double? depthScale,
  }) {
    return LightingConfig(
      lights: lights ?? this.lights,
      ambientIntensity: ambientIntensity ?? this.ambientIntensity,
      ambientColor: ambientColor ?? this.ambientColor,
      diffuseStrength: diffuseStrength ?? this.diffuseStrength,
      specularStrength: specularStrength ?? this.specularStrength,
      shininess: shininess ?? this.shininess,
      depthScale: depthScale ?? this.depthScale,
    );
  }
}
