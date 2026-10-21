# AI 主体与背景

当前源码新增主体、背景提取操作。入口位于右侧图层面板的 **AI 主体与背景**，也可从 **图层 → AI 主体与背景** 使用。

选中一个图像图层后，可选择：

- **主体到新图层**：识别前景主体，新建保留主体的图层。
- **背景到新图层**：反转主体覆盖范围，新建保留可见背景的图层。
- **分离主体与背景**：识别一次，分别生成背景、主体两个图层；主体在上。

结果均使用独立、可编辑的灰度蒙版，保留半透明边缘，不会将识别结果先转为硬边选区。新图层位于原图上方，保留原图的位置、旋转、翻转、所属文件夹、不透明度和混合模式。已有启用的蒙版会与新蒙版相乘；移动过的蒙版会先对齐到图像像素，停用的蒙版不参与提取。

原图保留并隐藏，可点击眼睛重新查看。一次操作可整体撤销或重做。输出图层和蒙版沿用现有 `.comp` 格式，保存后可以继续编辑，无需升级文件格式。若正在显示图层蒙版，生成结果后会返回正常画面。

空白图层、文件夹、调整图层、文字和形状，以及同时选择多个图层时，提取命令不可用。请先选中一个图像图层。提取始终分析该图层，不受当前选区限制；生成后清除旧选区。

**选择 → 主体**、**选择 → 背景** 分析整个可见画布，只创建选区。选区工具顶栏的 **AI 选择** 也提供这两个操作，并遵循当前的新建、添加或减去选区模式。

## 识别范围

识别复用项目已有的 Apple Vision `VNGenerateForegroundInstanceMaskRequest`，在本机执行，不上传图片、不要求 API 密钥，也不新增模型下载。它提取图像中显著的前景对象，不能保证每张图都能识别出合适的主体。未找到主体或识别失败时，保留原图和历史记录并显示错误。

背景提取保留照片中已有的背景像素，不会补画被主体遮挡的区域。头发、玻璃、低对比度边缘等场景可能需要继续手工调整蒙版；本功能不承诺与 Photoshop 的识别效果相同。需要原有边缘细化控件时，仍可使用 **滤镜 → 移除背景**。

## 实现参考

目标工作流为“识别 → 蒙版 → 新图层”。本次访问 Adobe 的 Select and Mask 文档超时，因而查阅了开源 [rembg 的蒙版与抠图流程](https://github.com/danielgatis/rembg/blob/main/rembg/bg.py)。实现保留 Compositor 原有的本机 Vision 识别和原生图层系统，没有引入 rembg 代码、Python 运行时或其模型。

## 验证

使用与 Swift 工具链匹配的 SDK：

```sh
python3 localization/generate.py --check
python3 localization/test_subject_extraction.py --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
python3 localization/build.py --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --output build/subject-extraction
```

`CompositorTests/SubjectExtractionTests.swift` 同时供 Xcode 测试目标和命令行回归使用，覆盖软蒙版、背景反转、选区方向、已有和移动过的蒙版、导出透明度、新图层与原图、文件夹、撤销重做、项目保存重开、错误恢复，以及异步识别期间切换文档。回归注入确定的识别蒙版，用于验证编辑流程；真实照片的识别质量需要另外检查。

2026-10-21 本机验证：使用 macOS 26.5 SDK 编译成功，六组命令行回归全部通过，测试应用签名验证通过。另用 [rembg 的公开人物样例](https://github.com/danielgatis/rembg/blob/main/examples/girl-1.jpg) 实际调用 Vision，检测到一个主体；在测试应用界面执行分离，确认生成两个带蒙版图层、原图隐藏，隐藏背景图层后主体四周显示透明棋盘格。系统图标生成、图片编码和 Vision 推理步骤需正常访问 macOS 服务，在受限执行环境外验证通过。未运行完整 Xcode 测试套件，也未据此评估所有照片的识别质量。
