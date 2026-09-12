# 政名政利公考800词

基于你提供的《高频800词.pdf》制作的个人离线 iOS 学习 App。目标设备：iPhone 14 Pro Max 和 iPad Pro 2021，系统16.5，均已安装 TrollStore。

通过 GitHub Tag 发布，GitHub Actions 自动构建 iPhone / iPad 共用 IPA，并上传到对应 Release。你不需要安装、打开或操作 Xcode；工程文件供 GitHub 云端自动构建使用。源码中的发布配置不代表已经构建成功，实际发布以 GitHub 运行结果为准，安装与双机同步仍需在设备上验收。

## 更新日志

以下记录源码变化，是否已经发布请查看仓库的 Releases 页面。每次更新在本节顶部增加新的 `### vX.Y.Z` 记录；正式 Release 自动读取与 Tag 完全相同的版本段。

### v2.2.2

- 优化：Release 安装包附件显示为“政名政利公考800词-v版本号.ipa”，版本自动跟随 Tag；校验文件同步更名。
- 优化：下载文件使用带版本号的稳定拼音名称，发布说明中的中文下载链接与实际文件对应；附件显示名核对完成后再正式发布新 Release。
- 保持：不改 Bundle Identifier、内部产品名、学习数据格式和现有 iPhone / iPad 打包流程。

### v2.2.1

- 优化：词条详情增加独立“个人笔记”卡片，位于释义下方、重点解析与关联词辨析上方；正文直接显示，支持添加、编辑和查看历史。
- 优化：移除“我的学习”中重复的笔记区域；沿用原笔记、历史、备份和附近同步记录，不迁移或重建数据。

### v2.2.0

- 新增：推送版本 Tag 后自动构建 IPA、创建 GitHub Release，并上传安装包、SHA-256 校验文件和构建信息。
- 新增：Release 更新说明模板；优先读取 README 对应版本记录，未填写时按实际 Git 提交生成说明。
- 优化：App 名称改为“政名政利公考800词”，首页标题改为“政名政利公考”；保留原资料的来源标注。
- 优化：包内版本由 Tag 确定，不依赖 Actions 运行次数；保留手动测试构建及现有 iPhone / iPad 共用打包流程。
- 修复：“我的”中版本号写死的问题，改为读取当前安装包版本；归档与 IPA 校验增加版本、应用名称一致性检查。

## 已写入的功能

- 五个模块：首页、词库、刷题、错词、我的。
- 词库支持词语、释义、关键词搜索，以及词形近似匹配；分类、学习状态筛选和错误次数排序。
- 逐词保存收藏、掌握程度、笔记及修订历史、错误次数及错题历史。错误次数可手动改为 0–99999，改成 0 不删除历史。
- 词卡先回忆再展开，用“忘记 / 模糊 / 记得”反馈；每日目标可调，中途退出可继续。
- 间隔复习：忘记约10分钟，模糊1天，连续记得按1、3、7、14、30天递增；到期词显示在首页。
- 本地巩固提醒默认时间20:00，首次需在“我的”开启并允许通知。每天一条，优先高频错词并搭配生词，点击进入词卡；不使用联网推送。
- 随机、分类和错词专项刷题；提交后显示正确答案、解析及相关词条。
- iPad 宽横屏下，词库/错词左侧选词、右侧详情；刷题左侧题干、右侧选项。窄窗口与竖屏使用单栏；提交前不显示答案和解析。
- 学习记录离线存储；“我的 → 附近设备同步”通过 Apple MultipeerConnectivity 连接另一台 iPhone / iPad。首次核对配对码，双方确认后加密传输，不经过服务器、不使用 iCloud、没有扫码或相机权限。
- 按事件 ID 去重合并，不直接相加两台的错误总数。双方独立修改的笔记、手动次数需选择结果；接收方还需检查变化并确认保存。
- 保留导出/导入备份，导入也有冲突预览；无账号、无电脑同步。仅在同步页面主动开启发现，退出或进入后台会停止连接。
- 词语朗读和原 PDF 页内查看。

设计采用原生学习卡片、大字词条、湖蓝重点和系统深浅色背景，借鉴回忆—反馈—复习的学习流程，不复制其他 App 的素材或品牌。

## 真实内容与边界

原 PDF 为28页，共874条词语记录；合并重复项后865个独立词条，保留所有出现页码与原释义。其中62个词仅出现在原资料删除项中，默认不加入新词计划，可在词库筛选中显示。

题库共974题：3道注明出处的国考/省考公开版本真题、106道自编逻辑填空模拟题、865道释义自测。**不是完整的历年真题库**，释义自测不冒充真题。

原资料未逐词提供独立例句，已为106词补充自编例句；其余759词没有虚构“原文例句”。15处词形校订均保留原文和校订说明。详情见 [内容来源](content/SOURCES.md) 与 [导入报告](content/import-report.json)。

## 发布方式

通过 Git Tag 管理版本，例如 `v1.0.0` 表示初始版本，`v1.1.0` 表示后续新增功能的版本。本次附件命名更新建议使用 **v2.2.2**；不要复用已有的 `v2.2.0` / `v2.2.1` Tag。

首次使用时，确认仓库允许 GitHub Actions，默认分支 `main` 和本次 Tag 指向的提交都包含新的 `.github/workflows/build.yml`、`tools/release.py` 和 `.github/release-template.md`。发布作业已声明 `contents: write`，使用 GitHub 自动提供的 `GITHUB_TOKEN`，不需要另填个人令牌或 Apple 签名证书。若组织限制了 Actions 或写权限，需先在仓库/组织设置中放行。

每次发布前，在“更新日志”最上方写入对应版本的真实变化。格式如下（仅为格式示例，不会作为真实更新记录提取）：

```markdown
### v1.0.0

- 新增：填写本版本新增功能。
- 优化：填写本版本优化内容。
- 修复：填写本版本修复问题。
```

在仓库目录打开终端，按下面五条命令发布。例如发布 `v1.1.0`：

```bash
git add .
git commit -m "release v1.1.0"
git tag v1.1.0
git push origin main
git push origin v1.1.0
```

本次建议把上面三处 `v1.1.0` 换成 `v2.2.2`，之后按实际版本递增。执行前检查待提交文件，勿混入私人备份；Tag 必须尚未存在，并指向包含全部改动的提交。无需手动改 `Info.plist` 或工程版本号。

推送 Tag 后，Actions 自动完成检查、编译、IPA 打包与校验；发布作业先上传到草稿并核对附件显示名，全部成功才正式发布 **Release vX.Y.Z**。打开仓库 **Releases → 对应版本 → Assets → 政名政利公考800词-vX.Y.Z.ipa**，即可直接下载安装包，不必再下载 Actions 的外层 ZIP。附带同名 `.sha256` 和 `release-metadata.json` 用于核对校验值、版本和源码提交；GitHub 自动提供的 Source code ZIP 不是安装包。

例如 `v2.2.2` 页面显示 `政名政利公考800词-v2.2.2.ipa`，实际下载文件为 `ZhengMingZhengLiGongKao800-v2.2.2.ipa`。中文显示名使用 GitHub 的附件 label；实际文件用拼音避免中文文件名被平台改写，校验文件内也使用真实下载文件名，不影响 TrollStore 安装。此规则对包含本次改动的新版本生效，不自动改名已经发布的附件。

发布说明来自 [.github/release-template.md](.github/release-template.md)，包含版本号、“更新内容”、“下载”和构建信息。若 README 没有该 Tag 的记录，使用上一较低且可达版本 Tag 之后的实际提交记录（最多30条）；首次发布列出最近提交。要让说明清晰易读，建议每次都填写更新日志。

正式 Tag 使用 `vX.Y.Z`，X 为1–9999，Y/Z 为0–99，不带前导零或测试版后缀。Tag `v2.2.0` 会让安装包版本号和构建版本都成为 `2.2.0`；重跑不改变版本，不使用 `run_number`。新发布应使用高于已安装版本的新 Tag，**不要强制移动或覆盖已发布 Tag**。

### 日常上传与手动测试

- 普通 `main` 推送只上传代码，不再自动构建或发布。也可以全程使用 GitHub Desktop：提交后在 History 中右键新提交 → Create Tag → 填版本号 → Push origin，详见上传指南。
- 保留 **Actions → Build IPA → Run workflow**。选择分支时仅生成测试制品，不创建 Release；版本使用工程默认值（当前2.1.0 / 构建3），外层制品名为 `Words800App-manual-<提交短哈希>-IPA`，里面的 IPA 为 `ZhengMingZhengLiGongKao800-v2.1.0-manual-<提交短哈希>.ipa`。
- 手动运行若明确以现有合法 Tag 为 ref，则构建并发布该 Tag；必须与实际检出的提交一致。构建失败或尚未正式发布的草稿，修正网络/权限问题后可在原 Tag 的运行页面重跑。
- 已经成功公开发布的版本，请用更高的新 Tag 更新。重跑旧 Tag 可能覆盖普通 Release 的同名附件；不可变 Release 会拒绝覆盖，不能保证重跑成功。新流程不会把已公开 Release 重新变回草稿。
- 如果改了代码，重跑旧任务仍是旧代码，应重新提交并发布一个新 Tag。
- 私有仓库的 Release 下载需要有权限的 GitHub 账号；不要为了下载安装包把含个人资料的仓库改为公开。

GitHub 触发规则与权限说明见 [工作流语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)，Release 步骤使用 [softprops/action-gh-release](https://github.com/softprops/action-gh-release)。

附件显示名与实际文件名的区别见 [GitHub Release assets API](https://docs.github.com/en/rest/releases/assets#update-a-release-asset)；[GitHub 官方建议](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)先完成草稿附件再发布，避免开启不可变 Release 后无法修改附件。如果首次发布在设置显示名时失败，草稿会保留；解决网络/权限问题后可重跑，不要提前手动发布未完成的草稿。

## GitHub 打包与安装

具体步骤见 [GitHub Desktop 上传与打包指南](上传指南.md)。

仓库根目录应直接包含以下内容，不要再套一层父文件夹：

```
.github/workflows/build.yml
Words800App.xcodeproj/
  project.pbxproj
  xcshareddata/xcschemes/Words800App.xcscheme
Words800App/
  *.swift
  Info.plist
  Assets.xcassets/
  Resources/library.json
  Resources/source.pdf
content/
tests/
tools/
```

工作流先解析 Tag 与更新说明、检查资料和工程，再执行学习规则、合并、同步协议、安全握手和布局规则测试，然后使用 GitHub 的 macOS / Xcode 环境构建手机/平板共用的真机 archive。通过原生 Bundle 验证后，仍按原流程封装并校验 `build/800词学习助手.ipa`，发布时将相同字节复制为 `build/release/ZhengMingZhengLiGongKao800-vX.Y.Z.ipa`。安装后桌面名称是“政名政利公考800词”，与 IPA 文件名无关。构建禁用发行证书签名，供 TrollStore 安装时处理；不是 App Store / TestFlight 安装包。

源码中的 `Words800App/Resources/` 不要删除。它在工程中只是分组，构建时 JSON 和 PDF 分别复制到 App 包根目录，不在安装包内创建自定义 `Resources` 文件夹。

最低部署版本15.0，Swift5，Bundle ID `com.peanut13.words800`。Bundle ID、内部产品名 `Words800App`、Scheme、资源布局与学习记录格式保持不变。两台均安装同一版 IPA，更新前导出备份，不要先卸载。

附近同步操作与断线处理见 [附近同步使用说明](附近同步使用说明.md)。

## 验证

Windows 可运行 `python tools/validate_project.py` 检查数据、资源和工程引用，以及 `python -B -m unittest discover -s tests -p 'test_*.py' -v` 运行回归测试（Python3.9及以上；发布测试另需 Git）。GitHub 会额外运行 `bash tools/verify_macos.sh` 和实际 iOS 编译。检查结果与真机待测项见 [TESTING.md](TESTING.md)。

内置 JSON、PDF、图标已经生成；上传打包不需要安装 Python 依赖、重新提取 PDF 或手动改源码。仅重新生成内容时才需要 pdfplumber / Pillow：

```text
python tools/inspect_pdf.py
python tools/build_content.py
python tools/build_assets.py
python tools/validate_project.py
```

原始资料仅供个人学习；上传前请确认你对资料的使用权限，不要把私人学习备份提交到仓库。
