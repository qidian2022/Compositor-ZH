# Compositor 中文版 1.5.3-zh.3（预览版）

新增两项在 Mac 本机运行的 AI 功能，无需账户、上传照片或额外下载模型。

- **AI 主体与背景**：从右侧图层面板或“图层 → AI 主体与背景”进入，将主体、背景提取为带可编辑软蒙版的新图层，或一键分离两者。原图保留并隐藏，支持撤销重做。也可通过“选择 → 背景”和选区工具栏的“AI 选择”创建选区。
- **AI 照片降噪**：从“滤镜 → AI 照片降噪”进入，支持强度调节、原图对比、处理进度、取消和选区处理，保留透明度及 16 位 SDR 精度。应用内附带 MIT 许可的 FFDNet 模型。

主体识别使用 Apple Vision，复杂边缘可能需要手工调整蒙版；背景提取不会补画被主体遮挡的区域。降噪支持 SDR 图层，HDR 需先转换。两项功能均不改变现有项目格式（版本 15）。

本版源码已合并到 `main`。裁剪、降噪、主体与背景专项回归、完整应用构建、签名和安装包完整性检查通过。本机没有完整 Xcode，未运行完整上游 Xcode 测试套件。功能范围见 [主体与背景说明](https://github.com/qidian2022/Compositor-ZH/blob/main/docs/ai-subject-background.md)及[照片降噪说明](https://github.com/qidian2022/Compositor-ZH/blob/main/docs/ai-denoise.md)。

## 安装

需要 Apple Silicon（M 系列）Mac 和 macOS 26 或更新版本。下载 Assets 中的 `Compositor-ZH-1.5.3-zh.3-arm64.dmg`，打开后把“Compositor 中文版.app”拖入 Applications。更新前保存项目并退出旧版，再选择替换。也提供同版本 ZIP 和 `SHA256SUMS.txt`。

本预览版采用 ad-hoc 临时签名，没有 Developer ID 签名或 Apple 公证。首次打开若被系统拦截，请到“系统设置 → 隐私与安全性”按提示选择“仍要打开”；无需关闭 Gatekeeper。
