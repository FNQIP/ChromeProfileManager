# 更新日志

本项目使用语义化版本号：`主版本.次版本.修订版本`。

## 1.0.0 — 首个公开版本

面向 Intel（x86_64）Mac，最低要求 macOS 13 Ventura。

### 新增

- 菜单栏常驻应用：无 Dock 图标、无主窗口，点击图标查看配置列表
- 自动发现 `~/ChromeProfiles/` 下的一级子目录作为独立 Chrome 用户数据目录
- 启动：以该目录作为 `--user-data-dir` 启动 Chrome，要求新窗口，参数独立传递
- 新建配置：创建空目录，由 Chrome 首次启动时初始化；名称校验与重名保护
- 复制配置：完整复制目录；源配置正在使用时禁止复制
- 删除配置：二次确认后移入废纸篓；正在使用时禁止删除
- 运行状态识别：通过 `sysctl(KERN_PROCARGS2)` 读取真实 argv，按规范化路径精确匹配
- 已运行提示：同一配置重复点击不会重复启动，而是提示「已在运行」
- 偏好设置：展示并打开配置根目录，支持自定义根目录（不移动、不删除旧目录）
- 状态未知时保守降级：禁用复制与删除
- `--diagnostics` 只读诊断输出，便于反馈问题
- 84 个单元测试 + 本地真实 Chrome 验收程序 `IntegrationCheck`
- 无 Xcode 构建脚本：SwiftPM Release 构建、Bundle 组装、架构校验、ad-hoc 签名、ZIP 与 SHA-256
- GitHub Actions：推送到 main 与 PR 时测试并在 Intel Runner 构建；推送 `v*.*.*` tag 自动发布 Release

### 已知限制

- 仅支持 Intel x86_64 与稳定版 Google Chrome
- 只管理「用户数据根目录」层，不管理 Chrome 内部的 `Default`、`Profile 1`
- 未签名、未公证，首次打开需通过「系统设置 → 隐私与安全性 → 仍要打开」放行
- 不提供开机自启
