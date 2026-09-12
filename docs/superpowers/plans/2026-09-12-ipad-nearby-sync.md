# iPad 横屏与附近设备同步实施计划

> 用户已确认：iPhone 14 Pro Max / iPad Pro 2021，均为 16.5，TrollStore 安装；只修改本地，不提交或上传。

## 目标与边界

同一 IPA 运行于手机和平板。宽屏刷题左右分栏，词库/错词列表与详情并排；窄窗口回归单栏。不得重新加入答案提示，解析仅在提交后展示。

附近同步采用 Apple MultipeerConnectivity（强制加密）和 CryptoKit 身份确认。仅用户主动打开同步页面时发现设备，两端确认配对后才传输学习备份；不接入公网、账号、服务器或 iCloud。App 进入后台时停止发现和连接，不承诺后台自动同步。

## 数据与交互契约

- 保持 study-v2.json 和事件格式兼容：事件 ID 去重，同 ID 不同内容拒绝，原子保存，保留上一版备份。
- SyncMergeEngine 只处理已通过验证的 StudySnapshot；比较双方相对共同事件的新增操作。双方独立修改同一词笔记时提示选择本机/对方/合并文本。
- 有手动错误次数调整且另一端也改了该词错误记录时，提示选择最终总数。不能直接相加两端总数；解决冲突时追加一条调整事件，保留原始错题历史。
- 收藏、掌握状态和复习时间按既有事件时间顺序重放；错题事件取并集。设置和未完成练习队列仍是设备本地配置。
- 同步发送方生成合并结果，双方均确认预览后各自原子保存。断线可能导致仅一端已保存，明确显示未完成；重试按 ID 去重收敛。保存前校验本地快照未改变，不能覆盖同步期间新记录。
- 不信任设备显示名称；握手加密密钥经配对校验确认。拒绝超限、损坏、异版本或题库不匹配的备份。

## 实施任务

- [x] 1. 自适应布局：PracticeView / WordLibraryView / ErrorWordsView / ContentView；宽窄窗口规则测试已写，旋转状态代码已审查，实际画面待真机。
- [x] 2. 测试先行编写 SyncMergeEngineTests，覆盖去重、并发笔记、手动归零、双方调整、重复同步、同 ID 篡改、过期预览；原生测试执行交由 GitHub。
- [x] 3. 合并引擎及 DataManager 的预览/提交接口；备份导入复用冲突处理。
- [x] 4. 附近传输层、配对校验、两端确认、超时/中断、SyncView 与 Profile 入口；安全握手测试已写，题库指纹校验已接入。用户最终确认不加扫码。
- [x] 5. Xcode 源文件注册、Bonjour/局域网权限、版本2.1/构建3、macOS 检查脚本与 GitHub 构建流程。用户无需安装或操作 Xcode。
- [x] 6. 全量内容/项目/语法检查、代码审查、使用说明与双机验收清单。

只读审查发现的“旋转销毁详情导致未保存草稿丢失”已通过浏览器外层持有编辑器修复并复审。详情滚动位置/关联词导航层级在单双栏切换时仍可能复位，不影响编辑窗口草稿。尚未执行 GitHub 原生测试/归档与双机实测，不将本地校验等同于完整验收。

## 验收与限制

Windows 运行 Python 回归和 Swift 语法解析；实际 Swift 编译及归档由现有 GitHub macOS 工作流执行。新原生测试加入同一工作流，不把语法通过表述为编译成功。最终还需用户在两台 16.5 真机检查横屏、首次局域网授权、配对、断线重试与学习记录一致性。

## 官方依据

- https://developer.apple.com/documentation/multipeerconnectivity
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- https://developer.apple.com/documentation/cryptokit/curve25519/keyagreement
