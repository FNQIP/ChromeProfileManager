# 安装与首次打开

## 1. 系统要求

- macOS 13 Ventura 或更高版本
- Intel（x86_64）Mac
- 稳定版 Google Chrome，默认位于 `/Applications/Google Chrome.app`

## 2. 下载

到本仓库的 **Releases** 页面下载：

- `ChromeProfileManager-<版本>-macOS-x86_64.zip`
- `ChromeProfileManager-<版本>-macOS-x86_64.zip.sha256`

## 3. 校验下载完整性

```bash
cd ~/Downloads
shasum -a 256 -c ChromeProfileManager-1.0.0-macOS-x86_64.zip.sha256
```

输出 `OK` 表示文件完整。若显示 `FAILED`，请重新下载，不要继续安装。

## 4. 安装

1. 双击 ZIP 解压
2. 把 `ChromeProfileManager.app` 拖进「应用程序」文件夹
3. 双击打开

## 5. 首次打开被系统阻止怎么办

应用没有 Apple Developer ID 签名，也没有公证，因此首次打开时 macOS 可能提示：

> 无法打开"ChromeProfileManager"，因为 Apple 无法验证此 App 是否包含恶意软件。

按以下顺序处理：

1. 先关闭这个提示，在 Finder 中**右键点按**应用图标，选择「打开」，再点「打开」
2. 如果仍然被拦截，打开「系统设置 → 隐私与安全性」，在页面下方找到关于 ChromeProfileManager 的提示，点「仍要打开」
3. 再次双击应用，系统会再确认一次，选择「打开」

之后应用即可正常启动，不再拦截。

### 请勿这样做

- **不要**全局关闭 Gatekeeper（`sudo spctl --master-disable`）
- **不要**把修改系统安全策略当作常规安装步骤
- **不要**对来源不明的文件执行放行操作

只对你自己确认来自本仓库 Releases 的文件点「仍要打开」。下载前请核对 SHA-256。

## 6. 验证安装成功

1. 菜单栏出现「叠放卡片」图标（没有 Dock 图标，也没有主窗口）
2. 点击图标，应看到配置列表；默认根目录为 `~/ChromeProfiles/`
3. 若该目录不存在，应用会自动创建

也可以用命令行验证菜单内容：

```bash
/Applications/ChromeProfileManager.app/Contents/MacOS/ChromeProfileManager --diagnostics
```

## 7. 卸载

1. 菜单栏图标 →「退出 Chrome Profile Manager」
2. 把应用从「应用程序」移到废纸篓
3. 如需清除偏好设置：

```bash
defaults delete io.github.chromeprofilemanager
```

`~/ChromeProfiles/` 中的配置目录属于你的浏览数据，卸载应用**不会**删除它们；如不再需要请自行在 Finder 中处理。
