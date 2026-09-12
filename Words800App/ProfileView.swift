import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("dailyGoal") private var dailyGoal = 20
    @State private var exportDocument = BackupDocument()
    @State private var exportPresented = false
    @State private var importPresented = false
    @State private var importPreview: SyncMergePreview?
    var body: some View {
        NavigationView {
            Form {
                Section("学习计划") {
                    Stepper("每天 \(dailyGoal) 词", value: $dailyGoal, in: 5...100, step: 5)
                    NavigationLink(destination: ReminderSettingsView()) {
                        Label("定时巩固 · 高频错词与生词", systemImage: "bell")
                    }
                }
                Section("我的积累") {
                    summary("词库总数", value: dataManager.words.count)
                    summary("未学习", value: dataManager.newWords.count)
                    summary("已掌握", value: dataManager.studyRecords.values.filter { $0.masteryLevel == .mastered }.count)
                    summary("错词数", value: dataManager.errorWords.count)
                    summary("收藏数", value: dataManager.favoriteWords.count)
                    NavigationLink(destination: SavedWordsView(favorites: true)) { Label("我的收藏", systemImage: "star") }
                    NavigationLink(destination: SavedWordsView(favorites: false)) { Label("学习记录", systemImage: "clock") }
                    NavigationLink(destination: QuestionHistoryView()) { Label("答题记录", systemImage: "list.bullet.rectangle") }
                }
                Section("设备与备份") {
                    NavigationLink(destination: NearbySyncView(dataManager: dataManager)) {
                        Label("附近设备同步 · iPhone / iPad", systemImage: "ipad.and.iphone")
                    }
                    Button {
                        do { exportDocument = BackupDocument(data: try dataManager.exportData()); exportPresented = true }
                        catch { dataManager.message = error.localizedDescription }
                    } label: { Label("导出学习记录", systemImage: "square.and.arrow.up") }
                    Button { importPresented = true } label: { Label("导入学习备份", systemImage: "square.and.arrow.down") }
                    Text("记录保存在本机。导出文件包含笔记、收藏、答题和错误次数；导入先预览，再合并。重复导入不会重复计数。卸载前请先导出备份。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("资料与版本") {
                    Text("花生十三800词智能学习 · 2.1")
                    Text("你的 PDF 包含成语与实词、增补和删除标记。所有词条保留原资料页码；自编例句与模拟题单独标注。")
                        .font(.footnote).foregroundColor(.secondary)
                    Text("离线使用；本地发音使用 iOS 语音。无需账号。").font(.footnote).foregroundColor(.secondary)
                }
            }.navigationTitle("我的")
                .fileExporter(isPresented: $exportPresented, document: exportDocument, contentType: .json, defaultFilename: "花生800词学习备份") { result in
                    if case .failure(let error) = result { dataManager.message = "导出失败：\(error.localizedDescription)" }
                }
                .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw DataManager.AppError.text("备份文件超过 20 MB。") }
                        importPreview = try dataManager.previewImport(Data(contentsOf: url))
                    } catch { dataManager.message = "导入失败：\(error.localizedDescription)" }
                }
                .sheet(item: $importPreview) { preview in BackupMergeView(preview: preview) }
        }.navigationViewStyle(.stack)
    }
    private func summary(_ title: String, value: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(value)").monospacedDigit().foregroundColor(.secondary) }
    }
}
struct ReminderSettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var time = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var saving = false
    @State private var status = ""
    var body: some View {
        Form {
            Section("每日巩固") {
                Toggle("开启本地提醒", isOn: $enabled)
                DatePicker("每天提醒时间", selection: $time, displayedComponents: .hourAndMinute).disabled(!enabled)
                Text("优先选择错误次数多、尚未掌握的词，并搭配未学习生词。通知直接显示词语和简短释义，点击后进入词卡复习。")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section {
                Button {
                    saving = true
                    Task {
                        let values = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let success = await dataManager.configureReminder(enabled: enabled, hour: values.hour ?? 20, minute: values.minute ?? 0)
                        status = dataManager.message
                        dataManager.message = ""
                        saving = false
                        if !success { enabled = UserDefaults.standard.bool(forKey: "reminderEnabled") }
                    }
                } label: { HStack { Text(saving ? "正在保存…" : "保存提醒设置"); if saving { Spacer(); ProgressView() } } }.disabled(saving)
                if !status.isEmpty { Text(status).font(.subheadline).foregroundColor(.secondary) }
                Button("打开本机通知设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Section("提醒规则") {
                Text("每天一条通知；每周轮换高频错词和生词，学习后更新内容。提醒由本机安排，不需要联网；两台设备的提醒开关各自设置。")
                Text("“忘记”安排约10分钟后复习；“模糊”安排明天；连续“记得”逐步延长至1、3、7、14、30天。复习到期显示在首页，定时通知固定在你选择的时间。")
                Text("首次开启需允许通知。专注模式、静音或系统通知设置可能影响提醒显示。")
            }.font(.footnote).foregroundColor(.secondary)
        }.navigationTitle("定时巩固").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear {
                enabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
                let hour = (UserDefaults.standard.object(forKey: "reminderHour") as? Int) ?? 20
                let minute = UserDefaults.standard.integer(forKey: "reminderMinute")
                time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
            }
    }
}
struct SavedWordsView: View {
    @EnvironmentObject var dataManager: DataManager
    let favorites: Bool
    private var words: [Word] {
        favorites ? dataManager.favoriteWords : dataManager.sorted(dataManager.words.filter { dataManager.getStudyRecord(for: $0.id).lastStudyDate != .distantPast }, by: .recent)
    }
    var body: some View {
        List {
            if words.isEmpty { Text(favorites ? "还没有收藏，去词库收藏想重点记忆的词。" : "完成一组学词后，学习记录会显示在这里。").foregroundColor(.secondary) }
            ForEach(words) { word in NavigationLink(destination: WordDetailView(word: word)) { WordRowView(word: word) } }
        }.navigationTitle(favorites ? "我的收藏" : "学习记录")
    }
}
struct QuestionHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var wrongOnly = false
    private var records: [QuestionRecord] { dataManager.questionRecords.reversed().filter { !wrongOnly || !$0.isCorrect } }
    var body: some View {
        List {
            Toggle("只看错题", isOn: $wrongOnly)
            if records.isEmpty { Text("暂无符合条件的答题记录。").foregroundColor(.secondary) }
            ForEach(records) { record in
                if let q = dataManager.questions.first(where: { $0.id == record.questionId }) {
                    NavigationLink(destination: QuestionExplanationView(question: q, selectedAnswer: record.selectedAnswer)) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(q.content).lineLimit(2)
                            HStack {
                                Text(record.isCorrect ? "正确" : "错误").foregroundColor(record.isCorrect ? .green : .red)
                                Text(record.answeredAt, style: .date).foregroundColor(.secondary)
                            }.font(.caption)
                        }
                    }
                }
            }
        }.navigationTitle("答题记录")
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
