# Chrome Profiles

原生 macOS 菜单栏小工具：把 `~/ChromeProfiles/` 下的每个一级子目录当作一个独立的 Chrome 用户数据目录，点一下就能用对应目录启动 Chrome，登录状态、Cookie、扩展和浏览数据彼此隔离。

- **Universal Binary**：Intel x86_64 与 Apple Silicon arm64 通用，最低 macOS 12.0 Monterey
- 纯 Swift + AppKit，Swift Package Manager 为唯一工程来源，无第三方 UI 框架
- 常驻菜单栏，没有 Dock 图标，没有主窗口
- 不读取、不修改 Chrome 的 `Local State`、`Preferences` 等内部文件
- 不修改 Chrome 默认用户目录，不迁移、不覆盖任何现有数据

## 下载

| 文件 | 用途 |
| --- | --- |
| `ChromeProfiles-<版本>-universal.dmg` | 推荐：双击挂载后拖入「应用程序」 |
| `ChromeProfiles-<版本>-universal.zip` | 备选：解压后拖入「应用程序」 |
| `SHA256SUMS.txt` | 两个分发包的 SHA-256 校验值 |

👉 **[获取最新版本](../../releases/latest)**（进入后选择最新 Release，在 Assets 中下载）

## 安装（DMG）

1. 下载 `ChromeProfiles-<版本>-universal.dmg`
2. 双击打开 DMG，把 `ChromeProfiles.app` 拖到 **Applications**
3. 首次启动：在「应用程序」中 **按住 Control 点按** 应用图标 → 选择「打开」→ 在弹窗中再点一次「打开」
4. 之后正常双击启动即可

首次打开可能提示「Apple 无法验证此 App 是否包含恶意软件」，这是未签名应用的正常提示。若没有看到「打开」选项，请到 **系统设置 → 隐私与安全性**，在页面下方找到该应用并点「仍要打开」。

> **本应用未使用 Apple Developer ID 签名，也未经过 Apple 公证（Notarization）。**
> 构建过程使用 ad-hoc 签名（`codesign -s -`），它只能满足 macOS 对可执行文件的基本要求，**不等于**开发者签名，也不代表 Apple 对该应用做过任何验证。本项目不需要 Apple 开发者账号。

### 可选：移除下载隔离标记

```bash
xattr -dr com.apple.quarantine /Applications/ChromeProfiles.app
```

⚠️ 该命令会移除下载隔离标记。**请仅在你确认下载来源可信（本仓库 Releases）时执行**，不要在来源不明的应用上使用。

**不要**为了安装本应用而全局关闭 Gatekeeper（例如 `sudo spctl --master-disable`），也不要修改系统安全策略作为常规步骤。

## 使用

启动后菜单栏出现「叠放卡片」图标：

```
Chrome Profiles
5 个配置 · 1 个运行中
──────────────────
姐            ▸ 打开 Chrome / 在访达中显示 / 复制到新配置… / 移入废纸篓…
● 我  运行中   ▸ 已在运行(禁用) / 复制(禁用) / 删除(禁用)
我（副）       ▸ …
──────────────────
新建配置…        ⌘N
刷新列表         ⌘R
打开配置根目录
偏好设置…        ⌘,
──────────────────
卸载 Chrome Profiles…
──────────────────
退出 Chrome Profiles   ⌘Q
```

- 退出本应用**不会**退出已经启动的 Chrome
- 同一个配置重复点击不会再开一个实例，而是提示「已在运行」
- 不同配置可以同时运行，互不影响
- 菜单打开时目录信息总是最新的；运行状态在后台扫描，结果到达后菜单会自动刷新

## 从源码构建

### 只装了命令行工具（不需要完整 Xcode）

```bash
xcode-select --install   # 如果还没装
git clone <this repo> && cd ChromeProfiles
./Scripts/build-app.sh
```

脚本会用 SwiftPM 分别编译 `x86_64-apple-macosx12.0` 与 `arm64-apple-macosx12.0`，再用 `lipo` 合并成 Universal Binary。

### 装了完整 Xcode

同一个脚本会自动优先使用 `xcodebuild`（`-scheme ChromeProfiles -configuration Release`），并显式传入：

```
ARCHS="x86_64 arm64"  ONLY_ACTIVE_ARCH=NO  MACOSX_DEPLOYMENT_TARGET=12.0
SWIFT_OPTIMIZATION_LEVEL=-O  DEAD_CODE_STRIPPING=YES
ENABLE_HARDENED_RUNTIME=NO  CODE_SIGNING_ALLOWED=NO  CODE_SIGNING_REQUIRED=NO
```

强制指定后端：

```bash
CPM_BUILD_BACKEND=xcode   ./Scripts/build-app.sh   # 必须用 Xcode
CPM_BUILD_BACKEND=swiftpm ./Scripts/build-app.sh   # 只用 SwiftPM
```

### 产物

```
build/ChromeProfiles.app
dist/ChromeProfiles-1.0.2-universal.zip
dist/ChromeProfiles-1.0.2-universal.dmg
dist/SHA256SUMS.txt
```

脚本依次完成：环境检查 → 图标生成 → Universal 构建 → `lipo -archs` 架构校验 → `vtool -show-build` 最低系统校验 → 组装 Bundle → ad-hoc 签名 → ZIP → DMG → SHA-256。

可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `CPM_VERSION` | 覆盖版本号（默认 1.0.2） |
| `CPM_BUILD_NUMBER` | 覆盖 Build 号 |
| `CPM_BUILD_BACKEND` | `auto` / `xcode` / `swiftpm` |
| `CPM_SKIP_DMG=1` | 不生成 DMG |
| `CPM_XCODE_STRICT=1` | xcodebuild 失败时不回退到 SwiftPM |

## 开发

```bash
swift build                          # 调试构建
swift test                           # 91 个单元测试（swift-testing）
swift run IntegrationCheck           # 本地真实 Chrome 验收（headless + 临时目录）
```

如果终端报 `sandbox_apply: Operation not permitted`（受限环境常见），给命令加上 `--disable-sandbox`。

应用本体支持只读诊断开关，输出环境信息与完整菜单结构：

```bash
./build/ChromeProfiles.app/Contents/MacOS/ChromeProfiles --diagnostics
```

## 工程结构

```
Sources/
  ProfileKit/            纯逻辑，可独立测试（无 AppKit）
    ProfileStore.swift         目录扫描 / 创建 / 复制 / 移入废纸篓
    ProfileName.swift          名称校验（空、空白、分隔符、穿越、隐藏、控制字符、长度）
    PathHelpers.swift          路径规范化与直接子目录判定
    ChromeLocator.swift        定位稳定版 Chrome
    ChromeLauncher.swift       组装 argv 并启动进程
    ProcessListing.swift       sysctl 读取进程与 argv
    ChromeUsageDetector.swift  --user-data-dir 匹配
    ProfileService.swift       编排 + 分步扫描（目录/进程/Chrome）+ 占用前置检查
    Preferences.swift          根目录偏好
  ProfileUI/             菜单表现层模型（无 AppKit，可在 CI 中测试）
  ChromeProfiles/        AppKit 外壳：状态项、菜单、对话框、偏好设置窗口
  IntegrationCheck/      本地验收程序（不打包进 .app）
Tests/
  ProfileKitTests/       目录、名称、启动参数、进程匹配、分步扫描、偏好
  ProfileUITests/        菜单结构、禁用规则、空状态、警告顺序
Scripts/
  build-app.sh           Universal 构建 + ZIP/DMG/校验
  make-icon.swift        代码绘制图标并生成 .icns
```

## 设计要点

- **运行状态检测**用 `sysctl(KERN_PROCARGS2)` 读原始 argv，而不是解析 `ps` 输出——后者用空格拼接参数，含空格的路径会失真。
- **路径比较**先 `standardizedFileURL` + `resolvingSymlinksInPath`，再去掉末尾斜杠；额外做一次大小写不敏感比较（默认 APFS 不区分大小写）。误判方向只会「多禁用一次操作」，不会误删。
- **异步扫描**：目录列举是同步的（一次 readdir，平价且保证菜单最新），进程扫描放在后台队列；结果到达后更新缓存并在菜单仍打开时刷新界面。
- **未知即保守**：读不到进程列表时状态标记为「未知」，复制和删除一律拒绝；每次复制/删除前还会重新同步校验一次。
- **启动参数**只由 `["--user-data-dir=<path>", "--new-window"]` 两个独立 argv 元素组成，从不拼接 shell 字符串。
- **删除**走 `FileManager.trashItem`，不做递归删除；每次操作都断言目标必须是根目录的直接子目录。

更详细的设计说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 持续集成与发布

- `.github/workflows/ci.yml`：在 `macos-14`、`macos-15`、`macos-15-intel` 上跑单元测试；在 `macos-15` 上构建 Universal Binary，校验 `lipo`/`vtool`/签名，生成 ZIP + DMG + SHA256SUMS，并在 `macos-13` 上用构建产物做冒烟测试。
- `.github/workflows/release.yml`：推送 `v*.*.*` tag 触发，重新跑测试与正式构建，上传 `zip`、`dmg`、`SHA256SUMS.txt` 三个附件到 GitHub Releases。
- 工作流只声明最小必要权限（`contents: read` / `contents: write`），不配置任何 Apple 证书、账号或公证凭据。

## 已知限制

- 只支持稳定版 Google Chrome（默认安装在 `/Applications` 或 `~/Applications`）
- 只管理「用户数据根目录」这一层，不管理 Chrome 内部的 `Default`、`Profile 1`
- 未签名、未公证，首次打开需要按上面的步骤手动放行
- 不提供开机自启（后续版本可加）
- 自定义根目录保存在 `UserDefaults`，切换不会移动旧目录中的配置

## 文档

- [安装与首次打开](docs/INSTALL.md)
- [故障排查](docs/TROUBLESHOOTING.md)
- [架构说明](docs/ARCHITECTURE.md)
- [验收记录](docs/ACCEPTANCE.md)
- [更新日志](CHANGELOG.md)

## 许可证

MIT，见 [LICENSE](LICENSE)。
