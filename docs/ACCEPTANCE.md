# 验收记录

## 环境

| 项目 | 值 |
| --- | --- |
| 机型 | Intel Mac（x86_64） |
| 系统 | macOS 15.8.2 (24H232) |
| 工具链 | Apple Swift 6.1.2，仅 Command Line Tools（`/Library/Developer/CommandLineTools`） |
| SDK | MacOSX 15.5 |
| Chrome | 稳定版，`/Applications/Google Chrome.app` |
| 构建目标 | `x86_64 + arm64`，`macosx12.0` |
| 构建后端（本机） | SwiftPM 双架构 + `lipo`（本机无完整 Xcode） |
| 构建后端（CI） | `xcodebuild`（存在失败回退到 SwiftPM） |

## 自动化测试

```
$ swift test
✔ Test run with 91 tests passed
```

覆盖范围：

- 名称校验：空、纯空白、`/`、`:`、`.`、`..`、含 `..`、隐藏名、控制字符、超长、中文与括号名
- 目录：根目录自动创建、根目录被文件占用、只列一级目录、排序、忽略隐藏项与符号链接、空目录复制
- 创建：空目录创建、重名拒绝、同名文件拒绝、非法名称不落盘
- 复制：内容完整（含嵌套目录）、目标冲突、源缺失、源在根目录外
- 删除：移出根目录、目录缺失、根目录外拒绝
- 启动参数：中文、空格、`&`、引号、日文、`%`、`#` 均为单个 argv 元素；末尾斜杠规范化；不含 shell 拼接
- 进程匹配：`sysctl` 缓冲区解析、中文参数、含空格路径、只读声明数量的 argv、`我` 与 `我（副）` 不混淆、忽略默认目录实例、忽略非 Chrome 进程、辅助进程识别、多进程聚合、`--flag value` 写法
- 分步扫描：目录列举不触发进程扫描、状态按路径返回、进程表不可读时全部未知、缓存缺失的两种降级
- 服务层：运行中禁止复制/删除、状态未知时保守拒绝、未运行时允许、已运行不再启动、Chrome 缺失提示、目录消失提示、启动失败保留数据
- 菜单模型：空状态、排序、运行中禁用规则、表头统计、Chrome 缺失警告、根目录错误抑制空状态、警告顺序、命令顺序与快捷键

## 本地真实 Chrome 集成验收

```
$ swift run -c release IntegrationCheck
✅ 22/22 项通过
```

使用真实 Chrome 二进制与临时根目录（`/tmp` 下），关键结果：

- 空目录创建后由 Chrome 自行生成 `Local State` / `Default`
- 启动后 `sysctl` 能识别对应 `--user-data-dir` 的进程
- 两个配置同时运行，进程集合不重叠
- 运行中：复制被拒、删除被拒、目录保留
- 真实 argv 中 `--user-data-dir` 与含空格/中文的目录路径完全一致
- 退出后状态回到「未运行」，可正常复制
- 整个过程中未修改 `~/ChromeProfiles` 中的任何数据

## Universal Binary 验证

```
$ lipo -archs build/ChromeProfiles.app/Contents/MacOS/ChromeProfiles
x86_64 arm64

$ vtool -show-build build/ChromeProfiles.app/Contents/MacOS/ChromeProfiles
… (architecture x86_64):  platform MACOS  minos 12.0  sdk 15.5
… (architecture arm64):   platform MACOS  minos 12.0  sdk 15.5

$ /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' …
12.0
```

## 运行时验证（本机）

```
$ ./ChromeProfiles.app/Contents/MacOS/ChromeProfiles --diagnostics
Chrome Profiles 诊断报告
版本：1.0.2
系统：Version 15.8.2 (Build 24H232)

== 配置根目录
/Users/<user>/ChromeProfiles（默认）
配置数量：5，运行中：0

== Chrome
/Applications/Google Chrome.app

== 菜单项（与打开菜单时一致）
  Chrome Profiles / 5 个配置 · 0 个运行中 [禁用]
  ──────────
  姐 [可点] ▸ 打开 Chrome | 在访达中显示 | 复制到新配置… | 移入废纸篓…
  老爸 [可点] ▸ 打开 Chrome | 在访达中显示 | 复制到新配置… | 移入废纸篓…
  老妈 [可点] ▸ 打开 Chrome | 在访达中显示 | 复制到新配置… | 移入废纸篓…
  我 [可点] ▸ 打开 Chrome | 在访达中显示 | 复制到新配置… | 移入废纸篓…
  我（副） [可点] ▸ 打开 Chrome | 在访达中显示 | 复制到新配置… | 移入废纸篓…
  ──────────
  新建配置… [可点]
  刷新列表 [可点]
  打开配置根目录 [可点]
  偏好设置… [可点]
  ──────────
  退出 Chrome Profiles [可点]

== 偏好设置窗口
构建成功，尺寸 480×328
```

另外确认：

- 菜单栏出现应用图标（20pt 画布，图形高度约 17.6pt，与系统图标相当），Dock 中无图标，无主窗口
- 已存在的 5 个示例目录被自动识别（未写死名称）
- 当某个配置正被 Chrome 使用时会显示「● 运行中」并禁用复制/删除（见提交记录中的诊断输出）

## 分发产物

```
dist/ChromeProfiles-1.0.2-universal.zip    1.7 MB
dist/ChromeProfiles-1.0.2-universal.dmg    2.0 MB
dist/SHA256SUMS.txt
```

DMG 实测：

```
$ hdiutil verify dist/ChromeProfiles-1.0.2-universal.dmg
checksum ... is VALID

$ hdiutil attach … && ls /Volumes/…
Applications -> /Applications
ChromeProfiles.app
```

挂载后的 app 内可执行文件为 `x86_64 arm64`，`codesign -dv` 显示 `Signature=adhoc`、`flags=0x2(adhoc)`，未出现 Developer ID；从 DMG 中直接运行 `--diagnostics` 正常输出。

ZIP 实测：解压后 `codesign --verify --deep --strict` 通过，无 `__MACOSX` 冗余目录。

## 资源占用（空闲 3 秒采样）

| 指标 | 实测 |
| --- | --- |
| 常驻内存（physical footprint） | 5.9 MB（Universal 1.0.2：约 6 MB） |
| 空闲 CPU | 0.00% |
| 后台轮询 / 网络请求 / 辅助进程 | 无 |

## 未由自动化完成、需人工确认的项

以下项目依赖真实鼠标操作与系统权限，自动化会话中无法代替，发布前请按此清单手动过一遍：

1. 点击菜单栏图标后菜单在屏幕上正确展开，图标在浅色/深色菜单栏下都清晰
2. 「新建配置…」输入框可正常输入中文、可取消
3. 「复制到新配置…」「移入废纸篓…」的对话框文案与按钮可用，删除后目录确实出现在废纸篓
4. 「偏好设置…」窗口可打开、可切换根目录、切换后旧目录内容不变
5. 下载 DMG → 拖入应用程序 → Control 点按打开 → 系统「仍要打开」放行成功
6. 在 Apple Silicon Mac 上确认应用正常启动（Universal 架构已由 `lipo` 验证，但未在真机运行）
7. 退出应用后已启动的 Chrome 仍在运行

上述 1–4 项的等效逻辑已由单元测试与 `--diagnostics` 输出覆盖；5–7 项只能在真实安装/真机路径中验证。
