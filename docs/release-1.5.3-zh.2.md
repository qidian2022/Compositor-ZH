# Compositor 中文版 1.5.3-zh.2（预览版）

修复裁剪比例选择及拖动；“原始比例”使用首次导入照片的比例。右侧新增可显示、隐藏和移除的裁剪蒙版，支持撤销重做与项目保存。隐藏时恢复完整画布，启用时导出尺寸按裁剪框缩小。

裁剪不会丢弃源像素，但合并等破坏性编辑仍可能丢弃画布外内容。

Apple Silicon / macOS 26+；临时签名，无 Developer ID 或公证。裁剪自动化回归、完整应用构建和签名检查通过，未运行完整上游 Xcode 测试与图形界面点击验证。详见 docs/validation-crop-zh.md。

## 安装

下载下方 Assets 中的 `Compositor-ZH-1.5.3-zh.2-arm64.dmg`，打开后把应用拖入 Applications。也提供 ZIP。首次打开若被拦截，到「系统设置 → 隐私与安全性」点击「仍要打开」并确认，无需关闭 Gatekeeper。更新前请保存项目并退出应用。

DMG、ZIP 和 SHA256SUMS.txt 随本次发布提供。
