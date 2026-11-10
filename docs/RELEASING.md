# 发布 Shoreline

公开发布采用 ad-hoc 签名。构建、DMG 打包和 GitHub Actions 使用 Xcode 与 macOS 自带工具。

## 仓库设置

确认仓库允许 GitHub Actions 运行。工作流使用仓库自动提供的 `GITHUB_TOKEN`，发布任务申请 `contents: write` 权限。组织或账号策略需要允许该权限。

依赖的 GitHub 官方 Actions 固定到完整提交 SHA。更新时需同步核对其版本与 SHA。

## 自动发布版本

1. 在 `Resources/Info.plist` 中更新 `CFBundleShortVersionString` 和 `CFBundleVersion`。版本号使用三段数字，例如 `0.1.2`，构建号使用递增整数。
2. 提交变更并推送 `main`，确认 CI 的 Apple Silicon 和 Intel 单元测试、打包脚本测试通过。
3. 为该提交创建与版本号一致的标签并推送。

   ```sh
   git tag -a v0.1.2 -m "Shoreline 0.1.2"
   git push origin v0.1.2
   ```

Release 工作流会核对标签与应用版本，运行打包回归测试和原生单元测试，然后构建 Universal App 和 DMG。App 与 DMG 均采用 ad-hoc 签名。工作流检查应用签名、两种架构、DMG 完整性和校验码。

构建完成后，从同一标签提交生成源码归档，先创建草稿 Release，上传全部附件后再公开发布。Release 正文包含安装指南和 GitHub 自动生成的变更记录。

每个版本包含以下附件。

```text
Shoreline-0.1.2-universal.dmg
Shoreline-0.1.2-universal.dmg.sha256
Shoreline-0.1.2-source.tar.gz
Shoreline-0.1.2-source.tar.gz.sha256
```

对应源码归档包括构建脚本、主题素材与许可文件，便于用户获取与二进制对应的 GPL 源码。GitHub 同时提供该标签的自动源码下载。

## 失败与重试

在仓库 Actions 页面查看失败步骤。工作流设有超时限制，同一版本的发布按顺序执行。

- 测试或构建失败时，修复后提交新变更，并使用新的版本号和标签发布。
- 如果构建已成功，网络或附件上传中断，可以重新运行失败的工作流。已有草稿 Release 会继续上传附件，完成后公开。
- 也可以在 Actions → Release → Run workflow 中选择工作流并填写已有版本标签，例如 `v0.1.2`，重新构建该标签。
- 已公开版本受重复发布保护，需要新的版本号和标签。
- 构建完成的附件还会作为 Actions artifact 保留 14 天，供下载排查。

## 本地打包

选中 Xcode 26 或更高版本后运行以下命令。

```sh
./scripts/release.sh --check
./scripts/release.sh

# 仅对打包产物指定版本和构建号
./scripts/release.sh 0.1.2 3
```

输出目录默认为 `dist/`，可通过 `DIST_DIR` 指定。已有同版本产物时，显式使用 `OVERWRITE=1` 才会替换。打包失败时保留 `.release.*` 工作目录，并输出其位置。

本地打包支持源码工作目录中的修改。正式对外发布使用标签工作流，确保发布包与源码归档对应。安装包中的根目录和应用资源中均包含许可与来源声明，DMG 根目录还包含安装指南。

## 发布前桌面验证

原生 UI 和 WebKit 渲染测试在可用图形桌面下运行。

```sh
./scripts/test.sh
./scripts/test-native.sh
```

确认 Finder 图标避让、暂停恢复、多显示器、点击壁纸展开桌面、台前调度和辅助功能授权。Intel 实机及不同 macOS 版本的表现需对应环境验证，CI 单元测试覆盖其纯逻辑部分。
