免费开源的中文 Photoshop 替代工具，面向 Apple Silicon / macOS 26+。这是 Compositor v1.5.3 的独立中文 fork，不是 Adobe Photoshop。

本次加入 1128 条翻译，覆盖菜单、工具、RAW 调色面板、混合模式与导出操作；保留图层、蒙版、选区、修复、文字与形状、摄影调色和多格式导出功能。相机 RAW 通过 Apple Core Image 显影，兼容性取决于系统。

### 下载

下载 `Compositor-ZH-1.5.3-zh.1-arm64.zip`，解压后将 `Compositor 中文版.app` 拖到应用程序。`SHA256SUMS.txt` 用于核对文件完整性。GitHub 自动生成的 Source code 文件是源码，不能直接当应用运行。

### 安装和兼容提醒

- **预览版，只有 ad-hoc 临时签名，没有 Developer ID 签名或 Apple 公证**；macOS 可能阻止打开。不需要关闭系统安全保护，可自行从源码构建。运行下载版前请确认来源并阅读 README 中的 Apple 安全打开说明。
- 8 位分层 PSD/PSB 支持 RGB 和 CMYK 导入（后者转换为 RGB）；不支持 PSD 导出，也不保证 Photoshop 无损往返兼容。16 位图像图层支持不等于 16 位分层 PSD 支持。
- 少量动态提示仍可能为英文，尚未完成完整 Xcode 测试、Z30 NEF 实拍和所有格式/HDR 工作流验证。
- 本分支关闭自动更新，请在本仓库获取后续版本。使用重要项目时请保留原片和备份。

原作品 Copyright (c) 2026 Wonder Assembly LLC，作者 Robbie Tilton。保留 MIT 许可及上游致谢。完整功能与验证范围见仓库 README 和 docs/validation-zh.md。
