# 构建与发布中文版

## 环境

Apple Silicon Mac，macOS 26+，Python 3，以及支持 macOS 26 的 Apple Swift 工具链。

本次发布验证使用 Apple Swift 6.4 与 macOS 26.5 SDK（Command Line Tools）。不要求完整 Xcode；Xcode 工程路径则需要完整 Xcode 26 或更新的匹配工具链。SDK 和编译器必须匹配。默认脚本使用 `xcrun --sdk macosx --show-sdk-path`；也可设置 `SDKROOT` 或传入 `--sdk /path/to/MacOSX.sdk`。不要跨工具链混用缺少 SwiftUI 宏插件的 SDK。

## 命令行构建

在仓库根目录：

```sh
python3 localization/generate.py --check
python3 localization/build.py
```

可显式选择安装好的 SDK：

```sh
python3 localization/build.py --sdk /path/to/MacOSX26.5.sdk
```

脚本从源码编译 Swift 和 C，每次重新编译 C 对象，直接从 `Compositor/Resources` 复制调色资源，从源码 PNG 生成 `.icns` 图标。不会读取 `/Applications` 下的现成应用，也不会下载任何二进制依赖。

产物是 `build/Compositor 中文版.app`，应用标识 `io.github.qidian2022.compositor-zh`，可与上游独立保存偏好设置。运行时版本为 `1.5.3-zh.3`（标准版本字段 1.5.3，构建号 15303）。仅 ad-hoc 签名，没有 Developer ID 或公证；命令行产物未启用 App Sandbox，权限由系统和用户文件操作控制。

## Xcode 工程

运行 `python3 localization/generate.py` 后打开 `Compositor.xcodeproj`，选择 Compositor scheme。工程会把 `Compositor/Resources/ChineseLocalization.json` 与其他资源一同打包。Sparkle 依赖和官方更新源已移除，团队 ID 已清空。Xcode 默认产物名仍为 `Compositor.app`，应用显示名为“Compositor 中文版”。发布 ZIP 和 DMG 使用上面的命令行构建脚本生成。

可执行上游测试：

```sh
xcodebuild test -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CompositorTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

本次发行机器没有完整 Xcode，因此不宣称完整套件已通过。仓库保留手动触发的 Xcode 测试工作流，另有每次 push/PR 触发的中文资源和命令行构建检查。

## 打包与发布

```sh
python3 localization/package.py
```

该命令在独立临时目录重新构建，再生成 `dist/Compositor-ZH-<版本>-arm64.dmg`、同版本 ZIP 与 `SHA256SUMS.txt`。文件名读取应用内的版本号。DMG 内含应用、Applications 快捷方式和中文安装说明，可拖动安装。有多个 SDK 时同样可以传 `--sdk`。不包含对象文件、缓存、日志和测试素材；仍为 ad-hoc 签名，没有 Developer ID 签名及公证。

每次发布更新都需要重新生成安装包：确认功能修改和版本号后，再运行上面这一条命令即可。不要在其他聊天仍修改功能源码时制作正式发行包；独立构建目录只能避免输出互相覆盖，不能冻结正在变化的源码。

若仅需将已经构建并验证的应用打成预览包，可跳过编译：

```sh
python3 localization/package.py --app "build/Compositor 中文版.app"
```

该方式会先复制应用到临时目录并验证签名；应确保输入应用没有被其他构建同时覆盖。正式发行优先使用默认的重新构建流程。校验文件只包含本次生成的同版本 DMG 和 ZIP。

发布前检查 Git 差异、资源一致性、签名验证和 GUI 冒烟测试，再把已提交的 `main` 分支打上 `v1.5.3-zh.3` 标签，上传 DMG、ZIP、校验文件及发布说明。标签必须指向实际构建的提交。发行仍标记为预览版，直到验证范围足够。

原上游的证书、公证配置及 Sparkle 发布脚本已替换，不能向上游更新源发布中文版。未来如加入 Developer ID 签名和公证，应由维护者配置自己的凭证，不要提交证书或密钥。
