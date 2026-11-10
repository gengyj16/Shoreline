# 安装 Shoreline

需要 macOS 13 或更高版本。名称带 `universal` 的安装包同时支持 Apple Silicon 和 Intel Mac。

## 下载与安装

1. 从本项目 GitHub 仓库的 Releases 页面下载 `Shoreline-版本号-universal.dmg` 和对应的 `.dmg.sha256`。
2. 在下载目录运行校验命令，将文件名中的版本号替换为实际版本。

   ```sh
   shasum -a 256 -c Shoreline-0.1.2-universal.dmg.sha256
   ```

3. 打开 DMG，将 `Shoreline.app` 拖到 Applications 文件夹，然后推出磁盘映像。
4. 从“应用程序”打开 Shoreline。

## 首次打开

发布包采用 ad-hoc 签名，未经 Apple 公证。macOS 可能提示无法验证开发者或无法验证应用是否包含恶意软件。

确认下载来源并完成校验后，先尝试打开应用，再前往“系统设置 → 隐私与安全性”，找到 Shoreline 的拦截提示，点击“仍要打开”，按系统提示确认。各版本 macOS 的提示文字可能略有差异。Apple 的说明包含对应操作步骤。[Apple 打开应用指南](https://support.apple.com/zh-cn/102445)

如果系统提示应用“已损坏”，先重新下载并核对 SHA-256。若校验一致、确认信任该下载，且系统设置未提供放行入口，可在终端对安装后的应用移除下载隔离属性，再打开应用。

```sh
xattr -dr com.apple.quarantine "/Applications/Shoreline.app"
open "/Applications/Shoreline.app"
```

此命令移除指定应用的下载隔离标记。校验码用于检查文件完整性，应用的发布来源仍需自行确认。

## 允许读取桌面图标

1. 在 Shoreline 设置窗口点击“打开授权设置”。
2. 在“系统设置 → 隐私与安全性 → 辅助功能”中开启 Shoreline。
3. 如果列表中没有 Shoreline，点击添加按钮，选择 `/Applications/Shoreline.app`。
4. 返回应用，等待连接 Finder 并读取桌面图标边界。

应用通过辅助功能读取 Finder 桌面图标的位置与尺寸，通过窗口元数据和命中测试判断桌面是否可见。主题资源随应用提供，程序离线运行。

## 更新与权限恢复

先通过菜单栏图标退出 Shoreline，再用新版本替换“应用程序”中的副本。ad-hoc 签名随构建内容变化，更新或移动应用后，macOS 可能要求重新授予辅助功能权限。如果应用持续提示需要权限，请在辅助功能列表中移除旧条目，重新添加安装后的应用并开启。

菜单栏图标可打开设置、切换主题、暂停动画和退出。退出后显示系统原有壁纸。
