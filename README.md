# Chrome Profile Manager

原生 macOS 菜单栏小工具：把 `~/ChromeProfiles/` 下的每个一级子目录当作一个独立的 Chrome 用户数据目录，点一下就能用对应的目录启动 Chrome，登录状态、Cookie、扩展和浏览数据彼此隔离。

- 纯 Swift + AppKit，Swift Package Manager 构建，不依赖 Xcode 工程、Electron 或任何第三方框架
- 常驻菜单栏，没有 Dock 图标，没有主窗口
- 不读取、不修改 Chrome 的 `Local State`、`Preferences` 等内部文件
- 不修改 Chrome 默认用户目录，不迁移、不覆盖任何现有数据
- 复制前检查占用，删除走废纸篓，不做递归删除

当前版本：**1.0.0**（Intel x86_64，最低 macOS 13）

## 功能

| 功能 | 说明 |
| --- | --- |
| 自动发现 | 每次打开菜单都重新扫描根目录，外部新建/删除的文件夹立刻可见 |
| 启动 | `--user-data-dir=<该配置目录> --new-window`，参数独立传递，中文/空格/特殊字符安全 |
| 新建 | 只创建空目录，由 Chrome 首次启动时自行初始化 |
| 复制 | 完整复制单个配置目录；正在运行时禁止复制 |
| 删除 | 移入 macOS 废纸篓；正在运行时禁止删除；二次确认 |
| 状态 | 通过 `sysctl(KERN_PROCARGS2)` 读取真实 argv，按规范化路径精确匹配进程 |
| 偏好设置 | 展示/打开配置根目录，可选自定义根目录（切换不移动、不删除旧目录） |
| 诊断 | `--diagnostics` 输出环境与菜单结构，便于排查问题 |

## 安装（普通用户）

1. 从 [Releases](../../releases) 下载 `ChromeProfileManager-<版本>-macOS-x86_64.zip`
2. 解压后把 `ChromeProfileManager.app` 拖进「应用程序」
3. 首次打开：在应用上右键 → 打开；若系统提示「无法验证开发者」，到「系统设置 → 隐私与安全性」点「仍要打开」

应用未签名、未公证，因此需要上述一次性放行。不要关闭 Gatekeeper，也不要用 `spctl --master-disable`。校验下载完整性的方法见 [docs/INSTALL.md](docs/INSTALL.md)。

## 使用

启动后菜单栏出现「叠放卡片」图标：

```
Chrome Profile Manager
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
退出 Chrome Profile Manager   ⌘Q
```

- 退出本应用**不会**退出已经启动的 Chrome
- 同一个配置重复点击不会再开一个实例，而是提示「已在运行」
- 不同配置可以同时运行，互不影响

## 从源码构建

只要求安装 Xcode Command Line Tools，**不需要**完整 Xcode，也不调用 `xcodebuild`。

```bash
xcode-select --install      # 如果还没有命令行工具
git clone <this repo> && cd ChromeProfileManager
./Scripts/build-app.sh
```

产物：

```
build/ChromeProfileManager.app                      # 可直接双击运行
dist/ChromeProfileManager-1.0.0-macOS-x86_64.zip    # 分发用
dist/ChromeProfileManager-1.0.0-macOS-x86_64.zip.sha256
```

脚本会依次完成：环境检查 → 图标生成 → 依赖解析 → `swift build -c release --triple x86_64-apple-macosx13.0` → 组装 Bundle → `lipo -archs` 架构校验 → ad-hoc 签名 → ZIP 与 SHA-256。

可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `CPM_VERSION` | 覆盖版本号（默认 1.0.0） |
| `CPM_BUILD_NUMBER` | 覆盖 Build 号 |
| `CPM_TARGET_TRIPLE` | 覆盖编译目标（默认 `x86_64-apple-macosx13.0`） |
| `CPM_SKIP_ZIP=1` | 只组装 .app，不打包 ZIP |

## 开发

```bash
swift build            # 调试构建
swift test             # 84 个单元测试
swift run IntegrationCheck   # 本地真实 Chrome 验收（headless，仅用临时目录）
```

如果终端报 `sandbox_apply: Operation not permitted`（受限环境常见），给命令加上 `--disable-sandbox`。

应用本体支持一个只读诊断开关：

```bash
./build/ChromeProfileManager.app/Contents/MacOS/ChromeProfileManager --diagnostics
```

## 工程结构

```
Sources/
  ProfileKit/        纯逻辑，可独立测试（无 AppKit）
    ProfileStore.swift        目录扫描 / 创建 / 复制 / 移入废纸篓
    ProfileName.swift         名称校验（空、空白、分隔符、穿越、隐藏、控制字符、长度）
    PathHelpers.swift         路径规范化与直接子目录判定
    ChromeLocator.swift       定位稳定版 Chrome
    ChromeLauncher.swift      组装 argv 并启动进程
    ProcessListing.swift      sysctl 读取进程与 argv
    ChromeUsageDetector.swift --user-data-dir 匹配
    ProfileService.swift      编排 + 占用前置检查
    Preferences.swift         根目录偏好
  ProfileUI/         菜单表现层模型（无 AppKit，可在 CI 中测试）
  ChromeProfileManager/  AppKit 外壳：状态项、菜单、对话框、偏好设置窗口
  IntegrationCheck/      本地验收程序（不打包进 .app）
Tests/
  ProfileKitTests/   84 项中的大部分：目录、名称、启动参数、进程匹配、偏好
  ProfileUITests/    菜单结构、禁用规则、空状态、警告顺序
Scripts/
  build-app.sh       无 Xcode 构建 + 打包 + 校验
  make-icon.swift    代码绘制图标并生成 .icns
```

## 设计要点

- **运行状态检测**用 `sysctl(KERN_PROCARGS2)` 读原始 argv，而不是解析 `ps` 输出——后者用空格拼接参数，含空格的路径会失真。
- **路径比较**先 `standardizedFileURL` + `resolvingSymlinksInPath`，再去掉末尾斜杠；额外做一次大小写不敏感比较，因为默认 APFS 卷不区分大小写。误判方向只会「多禁用一次操作」，不会误删。
- **未知即保守**：读不到进程列表时状态标记为「未知」，复制和删除一律拒绝。
- **启动参数**只由 `[`--user-data-dir=<path>`, `--new-window`]` 两个独立 argv 元素组成，从不拼接 shell 字符串。
- **删除**走 `FileManager.trashItem`，不做递归删除；每次操作都断言目标必须是根目录的直接子目录。

更详细的设计说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 已知限制

- 首发仅支持 Intel x86_64 与稳定版 Google Chrome
- 只管理「用户数据根目录」这一层，不管理 Chrome 内部的 `Default`、`Profile 1`
- 不做 Apple 开发者签名与公证，首次打开需要手动放行
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
