# 来源与许可

## Deskland Preview

Shoreline 使用 Deskland Preview 的沙滩与草地渲染器、主题参数、角色、图片和缩略图，并以独立的 Swift/AppKit/SwiftUI/WebKit 宿主适配 macOS。感谢 Deskland 作者提供原始实现与素材。[上游项目](https://github.com/BLEZZ0102/Deskland)

- 上游基准提交为 `9818b577402ff476e1b59da07970c56472713126`。
- 原代码与随附主题素材的版权归 Deskland authors 所有，Copyright (C) 2026 Deskland authors。
- 采用 GNU GPL version 3，完整条款见仓库根目录的 `LICENSE`。
- `Resources/Themes/` 中的 HTML、JavaScript、图片与主题参数来自上游，`themes.json` 仅保留沙滩与草地两个免费主题。
- 原始 `NOTICE` 与 `TRADEMARKS.md` 保存在 `Resources/Themes/`，随应用分发。

## 移植修改

以下修改由 Shoreline contributors 于 2026-11-10 完成，随本项目按 GPL-3.0 提供。

- 新增 Swift 原生宿主、设置界面、Finder 辅助功能图标读取、多显示器坐标转换、桌面可见性检测与日志。
- 新增 WebKit 消息桥接与应用内资源协议，以适配原主题在 macOS 上的运行。
- 修改两个主题的动画帧调度，暂停时取消 requestAnimationFrame，恢复时重新调度。
- 调整暂停状态下图标与参数变化的静态重绘，包括草地地形更新。
- 修改 `share.js` 中临时暂停与恢复的入口，使其与动画调度状态同步。
- 新增 macOS 构建、测试与打包工具，以及 Shoreline 独立应用图标。

Shoreline 的 macOS 宿主代码采用 GPL-3.0。项目名称与图标用于标识本独立修改版本，Deskland 名称用于说明来源，其商标规则见随附的 `Resources/Themes/TRADEMARKS.md`。

## 应用图标

Shoreline 图标为本项目通过生成式图像工具制作的原创素材，原图、Icon Composer 配置与生成说明保存在 `Resources/AppIcon/`，随项目按 GPL-3.0 提供。

## 系统框架

AppKit、SwiftUI、WebKit 与 ApplicationServices 由 macOS 提供，适用 Apple 的许可。
