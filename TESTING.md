# 验证记录

## Windows 已执行

- 原 PDF 重新提取：28页、874条来源记录、865个独立词条，重复项保留出现页码。
- 内容检查：词条/题目 ID 唯一且有效、四个互不重复选项、正确答案范围、题目关联词存在、题目来源和解析非空。
- 原 PDF SHA-256 与词库指纹一致，逐页数量与导入报告一致。
- 工程对象引用全部可解析，共享 Scheme 指向正确目标；所有9个 App Swift 源文件加入 Sources，library.json 和 source.pdf 分别加入资源复制阶段。
- Info.plist 解析与版本检查、图标 PNG 尺寸及 RGB 无透明通道检查。
- tree-sitter Swift 语法检查：9个 App 源文件加1个测试文件通过。此项不是 Swift 类型检查或 Xcode 编译。

## 用户提供的 GitHub 日志（2026-09-12）

日志文件：logs_93958996668.zip。本次没有代替用户操作远程仓库。

- 内容检查、plutil 工程检查、共享 Scheme 枚举通过。
- 实际 Swift 学习规则测试显示 PASS: 15 learning-engine assertions。
- iPhone ARM64 Swift 编译、链接和资源处理已完成。
- 归档结束阶段失败：Archive Missing Bundle Identifier，exit code 70；尚未产生可下载 IPA。

原因定位：日志明确复制出 Words800App.app/Resources。Apple 的 [Bundle Structures](https://developer.apple.com/go/?id=bundle-structure) 明确禁止 iOS App 包内自定义 Resources 文件夹。本地 Info.plist 及构建日志均存在 com.peanut13.words800，不是缺少 Bundle ID 配置。

修正：源码 Resources 目录保留为 PBXGroup，按文件复制 library.json / source.pdf 到 App 包根目录；App 使用 Bundle 根资源查找；IPA 校验读取新位置并拒绝旧布局。没有修改 Bundle ID、签名要求、词库内容或用户学习记录。

本地回归：tests/test_bundle_layout.py 的两项检查在旧配置下均失败，修正后均通过。检查实际资源构建阶段的复制目标，不把源码目录误当成最终包布局。

## 修正后的 GitHub 工作流待验证

1. 标准库内容/工程检查、资源布局回归测试、plutil 工程校验及共享 Scheme 枚举。
2. 实际 Swift 编译运行15个学习规则断言：答错累计、答对不累计、答对首次安排复习、手动增减/清零保留历史、非负次数、忘记10分钟、连续记得延长间隔、笔记顺序/历史、收藏取消、备份编码往返、实际答题统计。
3. iPhone Release archive 真机编译。
4. 使用原生 Foundation Bundle 读取归档的 Bundle ID、执行文件、JSON 和 PDF。
5. IPA CRC、Payload 目录、ARM64 Mach-O、Bundle ID、最低 iOS 版本、根目录词库/PDF 字节完整性和编译图标检查。

修正后的 iOS 编译、原生 Bundle 验证、归档和 IPA 安装尚未执行。此前日志通过的测试不等于修正后的完整打包通过。

## iPhone 14 Pro Max / iOS16.5 待验收

- TrollStore 安装，首次打开无闪退；五个模块、深浅色模式、大字体与键盘操作。
- 搜索“源远流长”、释义“历史悠久”、部分词形；分类切换与原资料删除词开关。
- 手动设置错误次数为5、2、0，排序符合预期，清零不删除既有错题；重启后保留。
- 答错一题只记录一次；查看正确答案及解析，错词关联正确。
- 词卡先隐藏答案，反馈后切换下一词；中途退出后继续；到期词与每日计数正确。
- 个人笔记、笔记历史、收藏和掌握程度重启后保持。
- 导出备份；更改记录后导入旧备份不覆盖新事件；相同文件导入两次不重复计数；畸形备份明确拒绝。
- 允许通知并临时设为几分钟后，锁屏核对内容、点击进入对应词卡，再改回20:00；关闭提醒应移除待发通知。
- 禁止通知时提示开启设置；飞行模式下学习、查看 PDF、保存记录可用。
- 覆盖更新安装前备份，确认更新后本地数据保留。
