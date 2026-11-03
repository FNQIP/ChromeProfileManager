# 故障排查

先跑一次诊断，输出会包含根目录、Chrome 路径、每个配置的运行状态和完整的菜单结构：

```bash
/Applications/ChromeProfileManager.app/Contents/MacOS/ChromeProfileManager --diagnostics
```

## 菜单栏看不到图标

- 菜单栏图标过多时，macOS 会隐藏右侧图标；试试调大屏幕分辨率、收起其他菜单栏项目，或在「系统设置 → 控制中心」中精简常驻项
- 确认进程在运行：`pgrep -fl ChromeProfileManager`
- 若同时安装了本项目的旧版本，可能有两个图标，退出旧版本即可

## 提示「未找到 Google Chrome」

应用只检查两个位置：

- `/Applications/Google Chrome.app`
- `~/Applications/Google Chrome.app`

请把稳定版 Chrome 放到「应用程序」文件夹。Chrome Beta / Dev / Canary 不在首发支持范围内。

## 提示「配置根目录不可用 / 不可写入」

- 检查 `~/ChromeProfiles` 是否被同名**文件**占用（必须是目录）
- 检查目录权限：`ls -ld ~/ChromeProfiles`
- 或在「偏好设置…」里换成另一个可写入的目录

## 新建配置时提示名称已存在

名称必须唯一，应用不会覆盖已有目录。请换一个名称，或先处理同名目录。

## 提示「名称不能包含 / 或 :」「不能是 . 或 ..」

配置名称会直接成为一个目录名，因此不能包含路径分隔符，也不能是 `.`、`..`、以 `.` 开头或包含 `..`。中文、空格、括号、`&`、`$` 等字符都可以正常使用。

## 想复制/删除，但操作被禁用

菜单里的「复制到新配置…」「移入废纸篓…」变灰，说明该配置正在被 Chrome 使用，或运行状态无法确认。

1. 切到对应的 Chrome 窗口，关闭该配置的**所有**窗口并完全退出
2. 回到菜单，点「刷新列表」
3. 状态显示「未运行」后即可复制或删除

应用不会强制结束 Chrome 进程，也不会清理锁文件。状态显示「未知」时同样不会执行可能破坏数据的操作——这是有意为之。

## 状态显示「未知」

说明读取进程列表失败（极少见，通常是系统限制）。此时复制和删除会被禁用，但「打开 Chrome」仍可用。可尝试重新启动应用或退出 Chrome 后刷新。

## 点了「打开 Chrome」没有反应

- 确认 Chrome 能从「应用程序」正常启动
- 若该配置已被打开，菜单会显示「已在运行」，点它会提示切换到对应窗口
- 若 Chrome 启动后立即崩溃，应用只会显示错误，不会修改配置目录；可尝试用同一目录手动启动排查：
  ```bash
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir="$HOME/ChromeProfiles/我"
  ```

## 同一个配置开了多个窗口/实例

应用在启动前会检测该目录是否已被使用，正常情况下不会重复启动。如果仍然出现，可能是检测不到进程（权限问题），或者你在终端手动启动过。

## 配置目录被外部删除或重命名了

菜单在每次打开时重新扫描，外部改动会自动反映。如果点击后提示「配置的目录已经不存在」，点「刷新列表」即可。

## 删除后想恢复

删除操作把目录移入**废纸篓**，在 Finder 中打开废纸篓，右键「放回原处」即可。

## 切换自定义根目录后旧配置不见了

切换根目录只是改变应用显示的位置，不会移动或删除旧目录里的内容。切回默认根目录（偏好设置 →「恢复默认」）即可看到原来的配置。

## 收集更多信息

```bash
# 版本与结构
/Applications/ChromeProfileManager.app/Contents/MacOS/ChromeProfileManager --diagnostics

# 架构
lipo -archs /Applications/ChromeProfileManager.app/Contents/MacOS/ChromeProfileManager

# 签名状态
codesign -dv /Applications/ChromeProfileManager.app 2>&1
```

反馈问题时请附上以上输出，并说明 macOS 版本、Chrome 版本与复现步骤。**不要**附带 `~/ChromeProfiles` 中的实际浏览数据。
