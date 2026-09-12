import SwiftUI
import AVFoundation
import PDFKit

struct WordLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var search = ""
    @State private var category = "全部分类"
    @State private var status = "全部状态"
    @State private var sort: WordSort = .original
    @State private var showArchived = false
    @State private var selectedWordID: UUID?
    private var filtered: [Word] {
        dataManager.sorted(dataManager.searchWords(keyword: search).filter {
            dataManager.belongs($0, to: category) && (showArchived || !$0.sourceDeleted)
            && (status == "全部状态" || dataManager.getStudyRecord(for: $0.id).masteryLevel.rawValue == status)
        }, by: sort)
    }
    var body: some View {
        AdaptiveWordBrowser(title: "词库", words: filtered, selection: $selectedWordID) { wide, compactDetail in
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Picker("分类", selection: $category) {
                            Text("全部分类").tag("全部分类")
                            ForEach(dataManager.categories, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label(category, systemImage: "line.3.horizontal.decrease.circle") }
                    Spacer()
                    Menu {
                        Picker("学习状态", selection: $status) {
                            Text("全部状态").tag("全部状态")
                            ForEach(MasteryLevel.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        Picker("排序", selection: $sort) {
                            ForEach(WordSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("显示原资料删除词", isOn: $showArchived)
                    } label: { Label("筛选与排序", systemImage: "slider.horizontal.3") }
                }.font(.subheadline).padding()
                HStack {
                    Text("\(filtered.count) 词 · \(sort.rawValue)")
                    Spacer()
                    if !search.isEmpty { Button("清空") { search = "" } }
                }.font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 8)
                List(filtered) { word in
                    AdaptiveWordLink(word: word, isWide: wide, selection: $selectedWordID, compactDetailPresented: compactDetail)
                        .listRowBackground(wide && selectedWordID == word.id ? AppStyle.accent.opacity(0.10) : Color(.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { dataManager.toggleFavorite(for: word.id) } label: { Label("收藏", systemImage: "star") }.tint(.orange)
                        }
                }.listStyle(.plain)
                if filtered.isEmpty {
                    Text("没有找到匹配词条。试试输入释义、部分词语，或调整筛选。")
                        .foregroundColor(.secondary).padding()
                }
            }
            .searchable(text: $search, prompt: "词语、释义、含义、关键词")
        }
    }
}
struct WordRowView: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word
    private var record: StudyRecord { dataManager.getStudyRecord(for: word.id) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(word.word).font(.title3.weight(.semibold))
                    if record.isFavorite { Image(systemName: "star.fill").foregroundColor(.orange).font(.caption) }
                    if word.sourceDeleted { Text("原资料删除").font(.caption2).foregroundColor(.secondary) }
                }
                Text(word.meanings.first ?? "").font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                Text(word.category + (word.subcategory.isEmpty ? "" : " · " + word.subcategory)).font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                Text(record.masteryLevel.rawValue).font(.caption).foregroundColor(record.masteryLevel.color)
                if record.errorCount > 0 { Text("错 \(record.errorCount)").font(.caption.bold()).foregroundColor(.red).monospacedDigit() }
            }
        }.padding(.vertical, 6)
    }
}

struct WordDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.presentWordEditor) private var presentWordEditor
    @StateObject private var speaker = WordSpeaker()
    let word: Word
    @State private var localEditorRequest: WordEditorRequest?
    private var record: StudyRecord { dataManager.getStudyRecord(for: word.id) }
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(word.word).font(.system(size: 34, weight: .bold))
                        Text(word.section + " · " + word.category).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { speaker.speak(word.word) } label: { Image(systemName: "speaker.wave.2.fill").font(.title2) }
                        .buttonStyle(.borderless).accessibilityLabel("朗读词语")
                }.padding(.vertical, 12)
            }
            WordMeaningSection(word: word)
            Section("个人笔记") {
                if !record.personalNotes.isEmpty {
                    Text(record.personalNotes)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Button { openEditor(.notes) } label: {
                    Label(record.personalNotes.isEmpty ? "添加笔记" : "编辑笔记", systemImage: "note.text")
                }
                if record.noteHistory.count > 1 {
                    DisclosureGroup("笔记历史（\(record.noteHistory.count)）") {
                        ForEach(record.noteHistory.reversed()) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.date, style: .date).font(.caption).foregroundColor(.secondary)
                                Text(event.value.isEmpty ? "（清空笔记）" : event.value).font(.subheadline).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            WordUsageSections(word: word)
            Section("我的学习") {
                Picker("掌握程度", selection: Binding(get: { record.masteryLevel }, set: { dataManager.updateMasteryLevel(for: word.id, level: $0) })) {
                    ForEach(MasteryLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button { openEditor(.errors) } label: {
                    HStack { Text("错误次数"); Spacer(); Text("\(record.errorCount) 次").monospacedDigit(); Image(systemName: "pencil") }
                }
                Toggle("收藏这个词", isOn: Binding(get: { record.isFavorite }, set: { _ in dataManager.toggleFavorite(for: word.id) }))
                if record.nextReviewDate != .distantFuture {
                    HStack { Text("下次复习"); Spacer(); Text(record.nextReviewDate, style: .date).foregroundColor(.secondary) }
                }
            }
            if !record.errorHistory.isEmpty {
                Section("错误历史（手动调整也会保留）") {
                    ForEach(record.errorHistory.reversed()) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            if let q = dataManager.question(for: event) {
                                NavigationLink(destination: QuestionExplanationView(question: q, selectedAnswer: Int(event.value))) {
                                    Text(q.content).font(.subheadline).lineLimit(3)
                                }
                            } else {
                                Text(event.kind == "rating" ? "学词反馈：忘记" : "手动调整：\((Int(event.value) ?? 0) > 0 ? "+" : "")\(event.value) 次")
                            }
                            Text(event.date, style: .date).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("原始资料") {
                Text("高频800词.pdf · 第 \(word.sourcePages) 页").font(.subheadline)
                if word.sourceDeleted { Text("原资料标注删除，保留供查阅；默认不加入新词计划。").foregroundColor(.secondary) }
                ForEach(Array(word.occurrences.enumerated()), id: \.offset) { _, occurrence in
                    if !occurrence.correctionNote.isEmpty { Text(occurrence.correctionNote).font(.footnote).foregroundColor(.orange) }
                }
                Button("查看 PDF 原页") { openEditor(.source) }
            }
        }
        .navigationTitle(word.word).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $localEditorRequest) { WordEditorSheet(request: $0) }
        .onDisappear { speaker.stop() }
    }

    private func openEditor(_ kind: WordEditorKind) {
        let request = WordEditorRequest(word: word, kind: kind)
        if let presentWordEditor = presentWordEditor { presentWordEditor(request) }
        else { localEditorRequest = request }
    }
}
struct WordMeaningSection: View {
    let word: Word
    var body: some View {
        Section("释义 · 原资料") {
            ForEach(Array(word.meanings.enumerated()), id: \.offset) { _, meaning in Text(meaning).lineSpacing(6).textSelection(.enabled) }
        }
    }
}
struct WordUsageSections: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word
    var body: some View {
        if !word.keyPoints.isEmpty { Section("重点解析 · 原资料用法提示") { Text(word.keyPoints).lineSpacing(6) } }
        if !word.confusableWords.isEmpty {
            Section("关联词与辨析") {
                ForEach(Array(word.confusableWords.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) {
                        if let related = dataManager.words.first(where: { $0.word == item.word }) {
                            NavigationLink(item.word, destination: WordDetailView(word: related)).font(.headline)
                        } else { Text(item.word).font(.headline) }
                        Text(item.difference).font(.subheadline).foregroundColor(.secondary).lineSpacing(4)
                    }.padding(.vertical, 4)
                }
            }
        }
        if !word.examples.isEmpty {
            Section("例句") {
                ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(example.sentence).lineSpacing(6)
                        Text(example.translation).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
struct ErrorCountEditor: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let word: Word
    @State private var input = ""
    @State private var loadedDraft = false
    private var validCount: Int? {
        guard let count = Int(input), (0...99999).contains(count) else { return nil }; return count
    }
    var body: some View {
        NavigationView {
            Form {
                Section(word.word) {
                    TextField("错误次数（0–99999）", text: $input).keyboardType(.numberPad)
                    HStack {
                        Button("减一次") { input = String(max(0, (Int(input) ?? 0) - 1)) }
                        Spacer()
                        Button("加一次") { input = String(min(99999, (Int(input) ?? 0) + 1)) }
                    }.buttonStyle(.borderless)
                }
                Text("修改总次数会保留已有错题历史。设为 0 后，该词会移出错词本；下次答错仍会自动累计。")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .navigationTitle("编辑错误次数").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { if let value = validCount { dataManager.setErrorCount(for: word.id, count: value); dismiss() } }.disabled(validCount == nil)
                }
            }
            .onAppear {
                guard !loadedDraft else { return }
                input = String(dataManager.getStudyRecord(for: word.id).errorCount)
                loadedDraft = true
            }
        }.navigationViewStyle(.stack)
    }
}
struct NotesEditorView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let word: Word
    @State private var notes = ""
    @State private var loadedDraft = false
    var body: some View {
        NavigationView {
            TextEditor(text: $notes).padding().navigationTitle("\(word.word) · 笔记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { dataManager.updateNotes(for: word.id, notes: notes); dismiss() }.disabled(notes.utf8.count > 100000) }
                }.onAppear {
                    guard !loadedDraft else { return }
                    notes = dataManager.getStudyRecord(for: word.id).personalNotes
                    loadedDraft = true
                }
        }.navigationViewStyle(.stack)
    }
}

final class WordSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.43
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

struct StudySessionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = WordSpeaker()
    let title: String
    let words: [Word]
    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var loaded = false
    private var current: Word? { queue.indices.contains(index) ? queue[index] : nil }
    private var sessionKey: String { "studySession." + title }
    var body: some View {
        NavigationView {
            Group {
                if let word = current {
                    ScrollView {
                        VStack(spacing: 22) {
                            HStack {
                                Text("\(index + 1) / \(queue.count) 词").monospacedDigit()
                                Spacer()
                                Text(word.category).lineLimit(1)
                            }.font(.caption).foregroundColor(.secondary)
                            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                            VStack(spacing: 18) {
                                Text(word.word).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                                Button { speaker.speak(word.word) } label: { Label("听发音", systemImage: "speaker.wave.2") }
                                Text(revealed ? "对照释义，判断自己是否记牢" : "先想一想：这个词是什么意思？").font(.subheadline).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 38)
                            if revealed {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(word.meanings.enumerated()), id: \.offset) { _, text in Text(text).lineSpacing(6) }
                                    if !word.keyPoints.isEmpty { Text(word.keyPoints).foregroundColor(AppStyle.accent).font(.subheadline) }
                                    ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                                        Text(example.sentence).font(.subheadline).padding(14).background(Color(.tertiarySystemFill)).cornerRadius(12)
                                    }
                                    NavigationLink("查看辨析、笔记和错误历史", destination: WordDetailView(word: word))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(24)
                    }.id(index)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 12) {
                            if revealed {
                                HStack(spacing: 10) {
                                    ratingButton("忘记", hint: "10分钟后", rating: 0, color: .red)
                                    ratingButton("模糊", hint: "明天", rating: 1, color: .orange)
                                    ratingButton("记得", hint: "延长间隔", rating: 2, color: AppStyle.accent)
                                }
                            } else {
                                Button { revealed = true } label: { Text("查看释义").frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent)
                            }
                        }.padding().background(.regularMaterial)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle").font(.system(size: 54)).foregroundColor(AppStyle.accent)
                        Text(queue.isEmpty ? "暂时没有待学词" : "这一组学完了").font(.title2.bold())
                        Text(queue.isEmpty ? "可以在词库选择词条，或到错词本进行专项复习。" : "今日已巩固 \(dataManager.todayLearnedCount) 个词。").foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("返回首页") { dismiss() }.buttonStyle(.borderedProminent)
                    }.padding()
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后继续") { saveProgress(); dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .tint(AppStyle.accent)
        .onAppear {
            guard !loaded else { return }; loaded = true
            if title != "提醒巩固", let saved = UserDefaults.standard.dictionary(forKey: sessionKey),
               let ids = saved["ids"] as? [String], let progress = saved["index"] as? Int, progress >= 0, progress < ids.count {
                let restored = ids.compactMap { id in dataManager.words.first { $0.id.uuidString == id } }
                if restored.count == ids.count { queue = restored; index = progress } else { queue = words }
            } else { queue = words }
            saveProgress()
        }
        .onDisappear { speaker.stop() }
    }
    private func ratingButton(_ title: String, hint: String, rating: Int, color: Color) -> some View {
        Button {
            guard let word = current, dataManager.rate(word.id, rating: rating) else { return }
            speaker.stop(); index += 1; revealed = false; saveProgress()
        } label: {
            VStack(spacing: 6) { Text(title).font(.headline); Text(hint).font(.caption2) }
                .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundColor(color)
                .background(color.opacity(0.10)).cornerRadius(14)
        }.buttonStyle(.plain)
    }
    private func saveProgress() {
        if index >= queue.count { UserDefaults.standard.removeObject(forKey: sessionKey) }
        else { UserDefaults.standard.set(["ids": queue.map { $0.id.uuidString }, "index": index], forKey: sessionKey) }
    }
}
struct SourcePDFView: View {
    @Environment(\.dismiss) private var dismiss
    let page: Int
    var body: some View {
        NavigationView {
            PDFPageReader(page: page).navigationTitle("原资料 · 第 \(page) 页").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }.navigationViewStyle(.stack)
    }
}
struct PDFPageReader: UIViewRepresentable {
    let page: Int
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true
        if let url = Bundle.main.url(forResource: "source", withExtension: "pdf") {
            view.document = PDFDocument(url: url)
            if let target = view.document?.page(at: max(0, page - 1)) { view.go(to: target) }
        }
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
