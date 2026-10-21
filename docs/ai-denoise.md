# AI 照片降噪

选中照片图层，打开 **滤镜 → AI 照片降噪**。默认强度为 50，可在 0–100 之间调整。放大至 100% 检查细节，取消勾选“预览”可查看原图；确认后只增加一次撤销记录。有选区时只改变选区内的像素。滤镜支持“上次使用的滤镜”。

模型随应用打包，照片和处理结果都留在本机，无需账户、网络服务或额外下载。大照片显示处理进度，取消和调整强度会在当前分块推理结束后停止旧任务。

## 参考与实现

交互参考 Adobe 的 [Denoise Demystified](https://blog.adobe.com/en/publish/2023/04/18/denoise-demystified) 和 [Camera Raw Enhance 文档](https://helpx.adobe.com/camera-raw/using/enhance.html)：强度滑杆、原图对比、检查细节。Adobe 的公开介绍没有提供可复用的模型权重；本功能不使用 Adobe 的专有实现，也不宣称效果相同。

推理使用 [KAIR](https://github.com/cszn/KAIR) 发布的 **FFDNet 彩色模型**，参考其 [网络结构](https://github.com/cszn/KAIR/blob/master/models/network_ffdnet.py) 和 [官方测试流程](https://github.com/cszn/KAIR/blob/master/main_test_ffdnet.py)。模型和改编的转换代码保留 Kai Zhang 的 MIT 许可，随应用附带 `LICENSE-FFDNet.txt`。论文：[FFDNet: Toward a Fast and Flexible Solution for CNN-Based Image Denoising](https://arxiv.org/abs/1710.04026)。

这是一款以高斯噪声为主训练的轻量神经网络，适合常见颗粒和彩色噪点。真实相机噪声、严重压缩和极暗场景的改善程度会不同；强度过高也可能损失纹理。

- 使用 Core ML 本地推理，允许系统调度 CPU、GPU 和 Neural Engine。
- 输入为未预乘透明度的 sRGB RGB 浮点数；强度 0 直接返回原图，其余值对应噪声标准差 `amount × 0.5 / 255`。
- 每块输入 256 × 256，保留 32 像素上下文，输出中心 192 × 192。偶数起点维持 PixelUnShuffle 相位，避免接缝。图像外部复制边缘像素，不缩小照片。
- 逐块读取 16 位像素，保留原透明度，输出保持原来的 8 位或 16 位深度。16 位图层的预览直接读取深色彩数据，确认时复用相同结果。
- 支持导入后的 JPEG、PNG、TIFF、HEIC 和已显影的 SDR RAW 照片图层。处理对象是 RGB 图层，不是相机 Bayer 原始数据。
- HDR 图层会提示先转换为 SDR，避免模型将高光截断。
- 结果保存为现有图层像素，项目格式没有变化。

## 重建模型

普通构建直接使用仓库中的 `Compositor/Resources/FFDNetColor.mlmodel`，无需 Python 机器学习依赖。Xcode 会编译模型；命令行构建复制模型，应用首次使用时交给 Core ML 编译。

需要重新转换时，在独立 Python 3.9 环境安装 `scripts/ai-denoise/requirements.txt`，从 [KAIR v1.0 官方发布](https://github.com/cszn/KAIR/releases/tag/v1.0) 下载 `ffdnet_color.pth`，运行：

```sh
python scripts/ai-denoise/convert_ffdnet.py --weights /path/to/ffdnet_color.pth
```

转换器严格检查参数名称和形状，比较 PyTorch 与 Core ML 的数值输出，并把源权重的 SHA-256 写入模型元数据。

已核验源权重 SHA-256：`286f04f7e3a20254c067ba95efb5d3339f4fc8a09a365a93cd469184d4cdb279`。转换器会拒绝不同的权重文件。

## 验证

无完整 Xcode 的 Apple Silicon Mac 可运行：

```sh
python3 localization/generate.py --check
python3 localization/test_ai_denoise.py --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
python3 localization/build.py --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --output build/ai-denoise
```

回归检查实际神经网络降噪后的误差、分块相位与接缝、透明度、奇数和极小尺寸、16 位输出、取消、HDR 保护，以及最新参数预览、原图对比、确认、撤销、重做和选区范围。
