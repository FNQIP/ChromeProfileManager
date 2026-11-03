# 安装与首次打开

## 1. 系统要求

- macOS 12.0 Monterey 或更高版本
- Intel（x86_64）或 Apple Silicon（arm64）Mac
- 稳定版 Google Chrome，默认位于 `/Applications/Google Chrome.app`

## 2. 下载

到本仓库的 **Releases** 页面选择最新版本，下载：

- `ChromeProfiles-<版本>-universal.dmg`（推荐）
- 或 `ChromeProfiles-<版本>-universal.zip`
- `SHA256SUMS.txt`（校验值）

## 3. 校验下载完整性

```bash
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

输出两个 `OK` 表示文件完整。若显示 `FAILED`，请重新下载，不要继续安装。

（只有下载了同一目录下的两个分发包时，`-c` 才会同时校验；也可以手工比对：

```bash
shasum -a 256 ChromeProfiles-1.0.1-universal.dmg
```）

## 4. 用 DMG 安装

1. 双击 `ChromeProfiles-<版本>-universal.dmg` 挂载
2. 把 `ChromeProfiles.app` 拖到窗口里的 **Applications** 快捷方式（即 `/Applications`）
3. 在 Finder 侧边栏推出安装镜像

用 ZIP 也可以：解压后同样把 `ChromeProfiles.app` 拖进「应用程序」。

## 5. 首次打开

1. 打开「应用程序」文件夹
2. **按住 Control 点按**（或右键点按）`ChromeProfiles`
3. 在菜单中选择「打开」
4. 系统弹窗中再点一次「打开」

完成这一次之后，后续直接双击即可正常启动。

### 如果仍然被阻止

打开「系统设置 → 隐私与安全性」，向下滚动，会看到类似「已阻止使用 ChromeProfiles，因为来自身份不明的开发者」的提示，点「仍要打开」，然后重新启动应用。

### 为什么会有这个提示

本应用**没有** Apple Developer ID 签名，也**没有**经过 Apple 公证（Notarization）。它只做了 ad-hoc 签名（`codesign -s -`），这是 macOS 对本地可执行文件的基本要求，**不代表**任何 Apple 层面的验证。本项目不需要 Apple 开发者账号，也不在 CI 中申请证书。

### 可选：移除下载隔离标记

```bash
xattr -dr com.apple.quarantine /Applications/ChromeProfiles.app
```

⚠️ 该命令会去掉 macOS 给下载文件打的隔离标记，让系统不再拦截。**只在你确认文件来自本仓库 Releases、且 SHA-256 校验通过时执行**。不要对来源不明的应用使用。

### 请勿这样做

- 不要全局关闭 Gatekeeper（`sudo spctl --master-disable`）
- 不要把修改系统安全策略当作常规安装步骤
- 不要把未签名应用当作「已公证」分发或宣传

## 6. 验证安装成功

1. 菜单栏出现「叠放卡片」图标（没有 Dock 图标，也没有主窗口）
2. 点击图标，应看到配置列表；默认根目录为 `~/ChromeProfiles/`
3. 若该目录不存在，应用会自动创建

命令行验证菜单内容：

```bash
/Applications/ChromeProfiles.app/Contents/MacOS/ChromeProfiles --diagnostics
```

## 7. 卸载

应用是纯菜单栏工具：没有后台服务、没有守护进程、不注册开机启动项，也没有系统级安装脚本。所以卸载就是「退出 + 删应用」，不残留任何东西在系统目录里。

1. 点菜单栏图标 →「退出 Chrome Profiles」（已启动的 Chrome 不会被关闭）
2. 把 `ChromeProfiles.app` 从「应用程序」移到废纸篓（用 DMG 装的记得先推出磁盘映像）
3. 如需清除偏好设置（只有改过「配置根目录」才会有数据）：

```bash
defaults delete io.github.chromeprofiles
```

4. 如需一并删除浏览数据（**不可恢复，请先确认**）：

```bash
# 先退出使用这些目录的 Chrome 窗口，再把目录移到废纸篓
open ~/ChromeProfiles            # 在 Finder 中确认内容
```

`~/ChromeProfiles/` 里的每个目录都是一份完整的 Chrome 用户数据（登录状态、Cookie、历史、扩展）。卸载应用**不会**删除它们；如果只想重装应用，保留这些目录即可，重装后配置列表会自动恢复。

### 从源码构建的版本

如果只是本地试用（例如 `~/Documents/.../ChromeProfiles/build/`）：

```bash
# 退出正在运行的实例
pkill -f "ChromeProfiles.app/Contents/MacOS/ChromeProfiles"
# 删掉整个仓库即可，.app 在 build/ 里，勾选 .gitignore 的产物不会被提交
rm -rf ~/Documents/New/ChromeProfiles
```
