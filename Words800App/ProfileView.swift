import SwiftUI

// MARK: - Profile View
struct ProfileView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingResetAlert = false

    var body: some View {
        NavigationView {
            List {
                // Statistics Section
                Section("学习数据") {
                    HStack {
                        Label("总词数", systemImage: "book.fill")
                        Spacer()
                        Text("\(dataManager.words.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("已学习", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(studiedCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("已掌握", systemImage: "star.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Text("\(masteredCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("错词数", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(dataManager.errorWords.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("收藏数", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                        Spacer()
                        Text("\(dataManager.favoriteWords.count)")
                            .foregroundColor(.secondary)
                    }
                }

                // Question Statistics
                Section("刷题数据") {
                    HStack {
                        Label("总题数", systemImage: "list.bullet.clipboard")
                        Spacer()
                        Text("\(dataManager.questions.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("已完成", systemImage: "checkmark.square.fill")
                            .foregroundColor(.blue)
                        Spacer()
                        Text("\(completedQuestions)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("正确率", systemImage: "chart.bar.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(accuracyRate)%")
                            .foregroundColor(.secondary)
                    }
                }

                // Quick Links
                Section("快捷功能") {
                    NavigationLink(destination: FavoriteWordsView()) {
                        Label("我的收藏", systemImage: "star.fill")
                            .foregroundColor(.orange)
                    }

                    NavigationLink(destination: StudyHistoryView()) {
                        Label("学习记录", systemImage: "clock.fill")
                            .foregroundColor(.blue)
                    }
                }

                // Settings
                Section("设置") {
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Label("重置学习记录", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.red)
                    }
                }

                // About
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("应用名称")
                        Spacer()
                        Text("花生十三800词")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("我的")
            .alert("重置学习记录", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) { }
                Button("确认重置", role: .destructive) {
                    resetData()
                }
            } message: {
                Text("这将清除所有学习记录、错题记录和笔记，但不会删除词库和题库。此操作不可恢复。")
            }
        }
    }

    private var studiedCount: Int {
        dataManager.studyRecords.values.filter { $0.masteryLevel != .unknown }.count
    }

    private var masteredCount: Int {
        dataManager.studyRecords.values.filter { $0.masteryLevel == .mastered }.count
    }

    private var completedQuestions: Int {
        Set(dataManager.questionRecords.map { $0.questionId }).count
    }

    private var accuracyRate: Int {
        guard !dataManager.questionRecords.isEmpty else { return 0 }
        let correct = dataManager.questionRecords.filter { $0.isCorrect }.count
        return Int(Double(correct) / Double(dataManager.questionRecords.count) * 100)
    }

    private func resetData() {
        dataManager.studyRecords.removeAll()
        dataManager.questionRecords.removeAll()
        dataManager.saveData()
    }
}

// MARK: - Favorite Words View
struct FavoriteWordsView: View {
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        List(dataManager.favoriteWords) { word in
            NavigationLink(destination: WordDetailView(word: word)) {
                WordRowView(word: word)
            }
        }
        .navigationTitle("我的收藏")
        .overlay {
            if dataManager.favoriteWords.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("暂无收藏")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Study History View
struct StudyHistoryView: View {
    @EnvironmentObject var dataManager: DataManager

    var recentStudiedWords: [Word] {
        let records = dataManager.studyRecords.values
            .filter { $0.masteryLevel != .unknown }
            .sorted { $0.lastStudyDate > $1.lastStudyDate }
            .prefix(50)

        let wordIds = records.map { $0.wordId }
        return dataManager.words.filter { wordIds.contains($0.id) }
            .sorted { word1, word2 in
                let date1 = dataManager.getStudyRecord(for: word1.id).lastStudyDate
                let date2 = dataManager.getStudyRecord(for: word2.id).lastStudyDate
                return date1 > date2
            }
    }

    var body: some View {
        List(recentStudiedWords) { word in
            NavigationLink(destination: WordDetailView(word: word)) {
                HStack {
                    WordRowView(word: word)

                    Spacer()

                    Text(timeAgo(from: dataManager.getStudyRecord(for: word.id).lastStudyDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("学习记录")
        .overlay {
            if recentStudiedWords.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("暂无学习记录")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)

        if days == 0 {
            return "今天"
        } else if days == 1 {
            return "昨天"
        } else if days < 7 {
            return "\(days)天前"
        } else if days < 30 {
            return "\(days / 7)周前"
        } else {
            return "\(days / 30)月前"
        }
    }
}
