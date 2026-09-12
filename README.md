# 花生十三800词学习助手

基于你提供的《高频800词.pdf》制作的个人离线 iOS 学习 App。目标设备：iPhone 14 Pro Max、iOS 16.5、已安装 TrollStore。

只改本地项目；由你使用 GitHub Desktop 提交、上传，再由 GitHub Actions 编译。Windows 不需要安装 Xcode。用户提供的首次构建日志显示学习规则测试及 Swift 编译通过，但归档失败；本地已修正资源包布局，需重新推送并验证完整打包。尚未真机验收。

## 已写入的功能

- 五个模块：首页、词库、刷题、错词、我的。
- 词库支持词语、释义、关键词搜索，以及词形近似匹配；分类、学习状态筛选和错误次数排序。
- 逐词保存收藏、掌握程度、笔记及修订历史、错误次数及错题历史。错误次数可手动改为 0–99999，改成 0 不删除历史。
- 词卡先回忆再展开，用“忘记 / 模糊 / 记得”反馈；每日目标可调，中途退出可继续。
- 间隔复习：忘记约10分钟，模糊1天，连续记得按1、3、7、14、30天递增；到期词显示在首页。
- 本地巩固提醒默认时间20:00，首次需在“我的”开启并允许通知。每天一条，优先高频错词并搭配生词，点击进入词卡；不使用联网推送。
- 随机、分类和错词专项刷题；提交后显示正确答案、解析及相关词条。
- 学习记录离线存储，支持导出和合并备份；无账号、无电脑同步、无后台网络服务。
- 词语朗读和原 PDF 页内查看。

设计采用原生学习卡片、大字词条、湖蓝重点和系统深浅色背景，借鉴回忆—反馈—复习的学习流程，不复制其他 App 的素材或品牌。

## 真实内容与边界

原 PDF 为28页，共874条词语记录；合并重复项后865个独立词条，保留所有出现页码与原释义。其中62个词仅出现在原资料删除项中，默认不加入新词计划，可在词库筛选中显示。

题库共974题：3道注明出处的国考/省考公开版本真题、106道自编逻辑填空模拟题、865道释义自测。**不是完整的历年真题库**，释义自测不冒充真题。

原资料未逐词提供独立例句，已为106词补充自编例句；其余759词没有虚构“原文例句”。15处词形校订均保留原文和校订说明。详情见 [内容来源](content/SOURCES.md) 与 [导入报告](content/import-report.json)。

## GitHub 打包

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

工作流先检查资料、工程和资源复制布局，再执行学习规则测试，然后使用 GitHub 的 macOS / Xcode 环境构建真机 archive，通过原生 Bundle 验证后封装并校验 `800词学习助手.ipa`。构建禁用发行证书签名，供 TrollStore 安装时处理；不是 App Store / TestFlight 安装包。

源码中的 `Words800App/Resources/` 不要删除。它在工程中只是分组，构建时 JSON 和 PDF 分别复制到 App 包根目录，不在安装包内创建自定义 `Resources` 文件夹。

最低部署版本15.0，Swift5，Bundle ID `com.peanut13.words800`，版本2.0。请保留 Bundle ID 以便后续更新同一应用。

## 验证

Windows 可运行 `python tools/validate_project.py` 检查数据、资源和工程引用。GitHub 会额外运行 `bash tools/verify_macos.sh` 和实际 iOS 编译。检查结果与真机待测项见 [TESTING.md](TESTING.md)。

内置 JSON、PDF、图标已经生成；上传打包不需要安装 Python 依赖、重新提取 PDF 或手动改源码。仅重新生成内容时才需要 pdfplumber / Pillow：

```text
python tools/inspect_pdf.py
python tools/build_content.py
python tools/build_assets.py
python tools/validate_project.py
```

原始资料仅供个人学习；上传前请确认你对资料的使用权限，不要把私人学习备份提交到仓库。
