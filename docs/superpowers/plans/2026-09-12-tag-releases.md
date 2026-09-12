# Tag 发布与应用更名实施计划

**Goal:** 按用户提供的发布规范，使推送 vX.Y.Z 自动构建 IPA 并创建带更新说明的 Release；应用改名为“政名政利公考800词”，首页为“政名政利公考”。

**Architecture:** 保留现有 macOS 构建、未签名归档、扁平资源包和 IPA 校验；构建只读权限，成功后由独立发布作业取得 contents:write。Tag 决定包内版本，不用运行次数。保留手动分支测试构建，但它不创建 Release。

**Tech Stack:** GitHub Actions / Python 标准库 / softprops/action-gh-release / 现有 Swift 与原生构建脚本。

**Spec:** 用户本次给出的五项发布目标、README 更新日志格式、发布模板与两处更名要求。

## 全局限制

- 仅改 C:/Users/ASUS/Desktop/花生800词/Words800App，不提交、打 Tag、推送或调用远程发布。
- Bundle ID 保持 com.peanut13.words800，产品名、Scheme、存储格式和资源路径不变。
- 原 IPA 仍生成于 build/800词学习助手.ipa，发布副本使用 build/release/Words800App.ipa，避免非 ASCII Release 附件名归一化。
- 合法正式标签为 v主.次.修订；版本不得来自 GITHUB_RUN_NUMBER。两端学习和附近同步代码不重构。
- 初始工作区干净，main 跟踪 origin/main；HEAD c5e574b，本地无 Tag。没有查询或更改远程状态。

## 任务与检查

- [x] tools/release.py 与 tests/test_release.py：测试优先实现 Tag/手动构建分流、非法标签拒绝、README 精确版本段提取（排除代码块）、基于实际 git 历史的更新说明回退、模板渲染、制品副本与 SHA256。函数边界 resolve_version(ref,event,defaults)、extract_changelog(markdown,tag)、prepare(root,environment)、stage(root)。对仓库操作仅只读；测试自己的临时 Git 仓库。
- [x] .github/workflows/build.yml：push.tags=['v*'] 加 workflow_dispatch；只读 build 输出确定版本并覆盖原生构建参数；全部原校验成功后归档发布文件；needs build 的 release 作业验证 checksum，再以 Release <tag> 创建并上传附件。每个 ref 串行，避免同版本并发覆盖。
- [x] Info.plist / project.pbxproj / ContentView.swift / ProfileView.swift / DataManager.swift：版本使用构建变量，保留 Bundle ID；修改桌面名、首页标题/副标题、版本页和通知品牌文案，版本页从实际 Bundle 读取。
- [x] tools/validate_project.py / tests/BundleArchiveCheck.swift：去除2.1/3硬编码，分别检查源码变量接线和实际归档/IPA 版本、品牌名、Bundle ID；保留原内容/资源校验。
- [x] README.md / 上传指南.md / .github/release-template.md / TESTING.md：Release 模板、真实待发布更新记录、完整五条命令、手动测试行为、失败重试与禁止移动已发布 Tag。既有内部2.1版本不伪装成已发布 Tag。
- [x] 运行 Python 全部测试、项目校验、Swift语法、工作流静态检查与只读审查。Windows 不执行原生编译，不能声称已生成 Release / IPA；用户上传 Tag 后由 GitHub 自动构建。

## 最终本地验证

- Python3.9 / 3.12 各23项测试通过；项目资料和工程校验通过；22个 Swift 文件语法解析通过；实际工作流 YAML 与权限/触发/依赖条件静态检查通过；git diff --check 通过。
- 只读审查发现 Python3.9 文件写入兼容问题，复现后修正，独立复审23项通过，无未解决的重要问题。
- 没有改变 HEAD、分支、真实仓库 Tag 或远程。实际 GitHub 原生编译、Release 发布和真机安装留待用户上传后验收，见 TESTING.md。
