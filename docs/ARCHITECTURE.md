# 架构说明

## 分层

```
┌───────────────────────────────────────────┐
│ ChromeProfileManager (AppKit 可执行目标)   │
│  状态栏图标 / NSMenu / NSAlert / 偏好窗口  │
└───────────────┬───────────────────────────┘
                │ 读取快照、调用动作
┌───────────────▼───────────────────────────┐
│ ProfileUI (纯 Swift)                       │
│  MenuModel：快照 → 菜单行、禁用规则        │
└───────────────┬───────────────────────────┘
                │ MenuSnapshot
┌───────────────▼───────────────────────────┐
│ ProfileKit (仅 Foundation)                │
│  ProfileStore / ChromeLocator / Launcher   │
│  ProcessListing / UsageDetector / Prefs    │
└───────────────────────────────────────────┘
```

依赖方向单一：UI 依赖模型，模型依赖逻辑，逻辑不反向依赖 UI。因此所有破坏性操作与进程判断都能在没有窗口服务、没有真实 Chrome 的 CI 环境里测试。

## 一次菜单打开发生了什么

1. `menuNeedsUpdate` 被 AppKit 调用
2. `ProfileService.listProfiles()` 同步读一次根目录（一次 `readdir`，开销极小），保证外部新建/删除的目录立刻可见
3. 运行状态优先用缓存；首次打开且无缓存时同步扫一次，避免菜单先闪一下「状态未知」
4. 组装 `ScanResult` → `MenuModel.make(from:)` → `[MenuRow]`（表头、警告、配置、空状态、命令）
5. 控制器按行生成 `NSMenuItem`，配置项带子菜单
6. 同时在后台队列启动一次进程扫描；结果回来后更新缓存，如果菜单还开着就原地重建一次（不会递归触发扫描）

没有定时器、没有高频轮询、没有常驻辅助进程。空闲时只有状态栏图标和菜单对象存在。

## 扫描策略（异步 + 缓存）

| 数据 | 时机 | 线程 | 理由 |
| --- | --- | --- | --- |
| 目录列表 | 每次打开菜单 | 主线程 | 一次 `readdir`，微秒级，换来「菜单永远是最新的」 |
| 运行状态 | 打开菜单后、操作后 | 后台队列 | 要遍历数百个进程并逐个 `sysctl(KERN_PROCARGS2)`，较重 |
| Chrome 定位 | 首次与启动预热 | 后台/主线程均可 | 两次 `stat` |

缓存失效与安全：菜单上的禁用状态只是展示，**每次复制/删除前都会重新同步校验运行状态**（`runningState(for:)`）。因此即使缓存短暂过期，也不会误删正在使用的配置。

操作（新建/复制/删除/切换根目录/刷新）完成后会同步扫一次状态再重建菜单，新出现的配置立刻有正确的状态，不会停留在「未知」。


## 运行状态识别

`ps` 输出把 argv 用空格拼起来，路径含空格时无法还原，因此改用 `sysctl(KERN_PROCARGS2)`：

```
[int argc][exec_path\0][padding \0...][argv0\0][argv1\0]...
```

解析后只保留 `argc` 个参数（后面紧跟的是环境变量）。匹配步骤：

1. 进程可执行路径必须位于 `.app/Contents/MacOS/` 或 `.framework/` 且包含 `Google Chrome`
2. 从 argv 中取 `--user-data-dir=<value>`（同时兼容 `-user-data-dir` 与「参数+值」分开写的形式）
3. 两侧路径都做 `~` 展开 → `standardizedFileURL` → `resolvingSymlinksInPath` → 去末尾斜杠
4. 先精确比较，再大小写不敏感比较（默认 APFS 卷不区分大小写）

第 4 步的宽松只会让「正在运行」的判定更容易成立，也就是更容易**阻止**操作，不会误删。`我` 与 `我（副）` 是不同路径，不会被混淆，这一点有专门的测试。

进程表整体读不到时，状态降级为 `.unknown`：复制与删除被拒绝，打开仍允许（Chrome 自己保证同一 `--user-data-dir` 只有一个实例）。

## 目录安全

- 所有写操作前调用 `assertDirectChild`，目标必须是根目录的**直接子目录**，避免任何递归操作
- 复制源也必须是根目录的直接子目录，防止把任意路径拷进来
- 删除使用 `FileManager.trashItem`，进废纸篓而不是直接 unlink
- 复制后重新 stat 目标目录，确认真实存在才报告成功
- 名称校验在文件系统调用之前完成：空、纯空白、`/`、`:`、`.`/`..`/含 `..`、以 `.` 开头、控制字符、超长（>100）

## 启动参数

```swift
["--user-data-dir=" + canonicalPath, "--new-window"]
```

永远是两个独立的 argv 元素，不经过 shell，不做引号转义。文件名里的空格、中文、引号、`;`、`$` 都不会被解释。

## 错误处理

- `ProfileStoreError` / `ProfileServiceError` / `ChromeLocatorError` / `ChromeLaunchError` 都实现 `LocalizedError`，带面向用户的中文描述与恢复建议
- Cocoa / POSIX 错误码被翻译为「权限不足」「磁盘已满」「目录不存在」等具体原因
- 所有错误都通过 `NSAlert` 呈现，不写进控制台了事

## 构建与分发

目标：**Universal Binary（x86_64 + arm64），最低 macOS 12.0**。`Scripts/build-app.sh` 有两个后端，产物一致：

**Xcode 后端**（有完整 Xcode 时自动优先，CI 使用）

```
xcodebuild -scheme ChromeProfiles -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_VERSION=5 \
  DEAD_CODE_STRIPPING=YES ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

**SwiftPM 后端**（仅装了 Command Line Tools 时）

```
swift build -c release --triple x86_64-apple-macosx12.0 -Xlinker -dead_strip -Xswiftc -O
swift build -c release --triple arm64-apple-macosx12.0  -Xlinker -dead_strip -Xswiftc -O
lipo -create -output ChromeProfiles …
```

两者都不把「仅 arm64」的编译选项写进通用配置——架构只由 `ARCHS` / `--triple` 决定，`ONLY_ACTIVE_ARCH=NO` 保证同时产出两个切片。

构建后固定做这些校验，任一不满足即失败：

1. `lipo -archs` 同时包含 `x86_64` 与 `arm64`
2. `vtool -show-build` 每个切片都是 `minos 12.0`
3. `Info.plist` 的 `LSMinimumSystemVersion` 为 `12.0`、`LSUIElement` 为 `true`
4. 组装后的 `.app` 内可执行文件仍是 fat binary
5. `codesign --verify --deep --strict` 通过，且为 ad-hoc（不出现 Developer ID）

分发：

- `ditto` 打 ZIP（`--norsrc --noextattr`，避免 `__MACOSX`）
- `hdiutil` 生成 UDZO DMG，内含 `ChromeProfiles.app` 与 `Applications` 符号链接
- `shasum -a 256` 生成 `SHA256SUMS.txt`
- ad-hoc 签名（`codesign -s -`）：不需要开发者账号，也不做公证；CI 不配置任何证书或公证凭据
- GitHub Actions：多版本 macOS 跑测试，`macos-15` 构建 Universal，`macos-13` 用产物做冒烟；tag 触发 Release 上传三个附件

## 不做的事

- 不读 Chrome 的 `Local State`、`Preferences`
- 不改 Chrome 默认用户目录
- 不强制结束 Chrome，不清理锁文件
- 不做遥测、不联网、不写数据库、不起后台服务
- 不使用 Apple Developer ID 证书，不做公证，不把未签名应用宣传成已公证

