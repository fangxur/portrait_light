"""
MiDaS Small → TFLite 转换脚本
============================
将 MiDaS v2.1 Small 模型从 PyTorch 转换为 TFLite 格式，
输出文件：midas_small_256.tflite

依赖：
    pip install torch torchvision onnx onnxruntime tensorflow

用法：
    python convert_midas_to_tflite.py

输出：
    ../assets/models/midas_small_256.tflite  （约 20MB）
"""

import os
import sys
import urllib.request

import numpy as np

OUTPUT_PATH = os.path.join(
    os.path.dirname(__file__), "../assets/models/midas_small_256.tflite"
)
INPUT_SIZE = 256


def download_midas_weights(cache_path: str) -> str:
    """从 GitHub 下载 MiDaS Small 权重"""
    url = (
        "https://github.com/isl-org/MiDaS/releases/download/v2_1/"
        "midas_v21_small_256.pt"
    )
    if not os.path.exists(cache_path):
        print(f"下载 MiDaS 权重: {url}")
        urllib.request.urlretrieve(url, cache_path)
        print("下载完成")
    else:
        print(f"使用缓存权重: {cache_path}")
    return cache_path


def export_to_onnx(weights_path: str, onnx_path: str):
    """导出为 ONNX 格式"""
    try:
        import torch
        import timm  # MiDaS Small 依赖 timm
    except ImportError:
        print("ERROR: 请安装 torch 和 timm: pip install torch timm")
        sys.exit(1)

    print("加载 MiDaS Small 模型...")
    # 使用 torch.hub 加载（更简便）
    model = torch.hub.load(
        "isl-org/MiDaS",
        "MiDaS_small",
        pretrained=True,
        trust_repo=True,
    )
    model.eval()

    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    print(f"导出 ONNX: {onnx_path}")
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        opset_version=12,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes=None,  # 固定尺寸，方便 TFLite 转换
    )
    print("ONNX 导出完成")


def convert_onnx_to_tflite(onnx_path: str, tflite_path: str):
    """ONNX → TensorFlow SavedModel → TFLite"""
    try:
        import onnx
        from onnx_tf.backend import prepare
        import tensorflow as tf
    except ImportError:
        print("ERROR: 请安装 onnx-tf 和 tensorflow:")
        print("  pip install onnx onnx-tf tensorflow")
        sys.exit(1)

    saved_model_dir = onnx_path.replace(".onnx", "_saved_model")

    # ONNX → TF SavedModel
    print("ONNX → TF SavedModel...")
    onnx_model = onnx.load(onnx_path)
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph(saved_model_dir)

    # TF SavedModel → TFLite
    print("TF SavedModel → TFLite...")
    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]  # FP16 量化（减小体积）
    tflite_model = converter.convert()

    os.makedirs(os.path.dirname(os.path.abspath(tflite_path)), exist_ok=True)
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    size_mb = len(tflite_model) / 1024 / 1024
    print(f"TFLite 已保存: {tflite_path}  ({size_mb:.1f} MB)")


def verify_tflite(tflite_path: str):
    """简单验证 TFLite 模型可以正常推理"""
    try:
        import tensorflow as tf
    except ImportError:
        return

    print("验证 TFLite 模型...")
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    print(f"  输入 shape: {input_details[0]['shape']}")
    print(f"  输出 shape: {output_details[0]['shape']}")

    # 随机输入测试
    dummy = np.random.rand(1, INPUT_SIZE, INPUT_SIZE, 3).astype(np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])
    print(f"  输出范围: [{output.min():.3f}, {output.max():.3f}]")
    print("验证通过 ✓")


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    cache_dir = os.path.join(script_dir, ".cache")
    os.makedirs(cache_dir, exist_ok=True)

    onnx_path = os.path.join(cache_dir, "midas_small_256.onnx")

    print("=" * 50)
    print("MiDaS Small TFLite 转换工具")
    print("=" * 50)

    # 步骤 1: 导出 ONNX（通过 torch.hub 自动下载权重）
    export_to_onnx(None, onnx_path)

    # 步骤 2: ONNX → TFLite
    convert_onnx_to_tflite(onnx_path, OUTPUT_PATH)

    # 步骤 3: 验证
    verify_tflite(OUTPUT_PATH)

    print("\n完成！模型文件：", os.path.abspath(OUTPUT_PATH))
