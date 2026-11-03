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
2. `ProfileService.snapshot()` 做一次扫描：列根目录一级子目录 → 读一次进程表 → 定位 Chrome
3. `MenuModel.make(from:)` 把快照转成 `[MenuRow]`（表头、警告、配置、空状态、命令）
4. 控制器按行生成 `NSMenuItem`，配置项带子菜单

没有定时器、没有后台轮询、没有常驻辅助进程。空闲时只有状态栏图标和菜单对象存在。

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

- 只用 `swift build -c release --triple x86_64-apple-macosx13.0`，不生成 Xcode 工程，不调用 `xcodebuild`
- 脚本手工组装 `.app`（`Info.plist` + `LSUIElement=true` + 图标），`lipo -archs` 校验必须包含 `x86_64`
- ad-hoc 签名（`codesign -s -`）：不需要开发者账号，也不做公证
- `ditto` 打 ZIP，`shasum -a 256` 生成校验文件
- GitHub Actions 在 Intel Runner 上重复同样的流程；Release 由 tag 触发并重新测试

## 不做的事

- 不读 Chrome 的 `Local State`、`Preferences`
- 不改 Chrome 默认用户目录
- 不强制结束 Chrome，不清理锁文件
- 不做遥测、不联网、不写数据库、不起后台服务
