# 花生十三800词学习助手

一款专为公务员考试设计的词汇学习 iOS 应用。

## ✨ 功能特点

- 📚 **完整词库** - 800个高频词汇，含拼音、释义、重点解析
- ✍️ **智能刷题** - 真题+模拟题，三种练习模式
- 📊 **学习记录** - 错误统计、个人笔记、掌握程度追踪
- ⭐ **错词系统** - 自动生成错词列表，针对性强化训练

## 📦 获取 IPA

### 自动构建（推荐）

1. **上传代码到 GitHub**
2. **启用 Actions** - 进入仓库 → Actions → 启用工作流
3. **运行构建** - 点击 "Build IPA" → "Run workflow"
4. **下载 IPA** - 等待 5-10 分钟后，在 Artifacts 中下载

### 安装方法

使用 **TrollStore** 安装：
1. 将 IPA 传到 iPhone（AirDrop）
2. 在"文件"应用中找到 IPA
3. 分享 → TrollStore
4. 等待安装完成

## 🛠 技术说明

- **语言**: Swift 5.0
- **框架**: SwiftUI
- **最低系统**: iOS 15.0
- **Bundle ID**: com.peanut13.words800

## 📱 应用结构

```
Words800App/
├── Words800App.xcodeproj/    # Xcode 项目文件
├── Words800App/               # 源代码
│   ├── Words800App.swift      # 应用入口
│   ├── Models.swift           # 数据模型
│   ├── DataManager.swift      # 数据管理
│   ├── ContentView.swift      # 主界面
│   ├── WordLibraryView.swift  # 词库界面
│   ├── PracticeView.swift     # 刷题界面
│   ├── ErrorWordsView.swift   # 错词本
│   ├── ProfileView.swift      # 个人中心
│   ├── Info.plist             # 应用配置
│   └── Assets.xcassets/       # 资源文件
└── .github/workflows/         # GitHub Actions
```

## 📝 项目配置

- **Product Name**: Words800App
- **Bundle Identifier**: com.peanut13.words800
- **Version**: 1.0
- **Display Name**: 花生十三800词

## 🔧 本地编译（需要 Mac）

```bash
xcodebuild -project Words800App.xcodeproj \
  -scheme Words800App \
  -configuration Release \
  -archivePath build/Words800App.xcarchive \
  archive
```

## 📄 许可证

本项目仅供个人学习使用。

---

🎓 祝你学习顺利！
