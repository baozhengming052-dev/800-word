import SwiftUI
import AVFoundation
import PDFKit
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private struct NewWordQuestionRequest: Identifiable {
    let id: UUID
}

struct WordLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var search = ""
    @State private var category = "全部分类"
    @State private var status = "全部状态"
    @State private var sort: WordSort = .original
    @State private var showArchived = false
    @State private var personalOnly = false
    @State private var personalArchived = false
    @State private var addingWord = false
    @State private var selectedWordID: UUID?
    @State private var savedWordAwaitingQuestion: UUID?
    @State private var showQuestionPrompt = false
    @State private var immediateQuestionRequest: NewWordQuestionRequest?
    private var filtered: [Word] {
        dataManager.sorted(dataManager.searchWords(keyword: search, includePersonalArchived: personalArchived).filter {
            dataManager.belongs($0, to: category) && (showArchived || !$0.sourceDeleted)
            && (status == "全部状态" || dataManager.getStudyRecord(for: $0.id).masteryLevel.rawValue == status)
            && (!personalOnly || $0.isPersonal)
            && (!personalArchived || dataManager.archivedWordIDs.contains($0.id))
        }, by: sort)
    }
    var body: some View {
        let displayedWords = filtered
        AdaptiveWordBrowser(title: "词库", words: displayedWords, selection: $selectedWordID) { wide, compactDetail in
            VStack(spacing: 0) {
                Picker("词库范围", selection: $personalOnly) {
                    Text("全部").tag(false); Text("我的添加").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)
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
                        Toggle("只看个人归档词", isOn: $personalArchived)
                    } label: { Label("筛选与排序", systemImage: "slider.horizontal.3") }
                }.font(.subheadline).padding()
                HStack {
                    Text("\(displayedWords.count) 词 · \(sort.rawValue)")
                    Spacer()
                    if !search.isEmpty { Button("清空") { search = "" } }
                }.font(.caption).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 8)
                List(displayedWords) { word in
                    AdaptiveWordLink(word: word, isWide: wide, selection: $selectedWordID, compactDetailPresented: compactDetail)
                        .listRowBackground(wide && selectedWordID == word.id ? AppStyle.accent.opacity(0.10) : Color(.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { dataManager.toggleFavorite(for: word.id) } label: { Label("收藏", systemImage: "star") }.tint(.orange)
                        }
                }.listStyle(.plain)
                if displayedWords.isEmpty {
                    Text("没有找到匹配词条。试试输入释义、部分词语，或调整筛选。")
                        .foregroundColor(.secondary).padding()
                }
            }
            .searchable(text: $search, prompt: "词语、释义、含义、关键词")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button { addingWord = true } label: { Label("添加词条", systemImage: "plus") }
            } }
        }
        .sheet(isPresented: $addingWord) {
            PersonalWordEditor(onSaved: savedNewWord, onUseExisting: selectSavedWord)
        }
        .onChange(of: addingWord) { isPresenting in
            guard !isPresenting, savedWordAwaitingQuestion != nil else { return }
            showQuestionPrompt = true
        }
        .confirmationDialog(questionPromptTitle, isPresented: $showQuestionPrompt, titleVisibility: .visible) {
            Button("立即添加题目") {
                guard let id = savedWordAwaitingQuestion else { return }
                immediateQuestionRequest = NewWordQuestionRequest(id: id)
                savedWordAwaitingQuestion = nil
            }
            Button("稍后再说", role: .cancel) { savedWordAwaitingQuestion = nil }
        } message: {
            Text("题目会自动关联这个词；录入后可直接在刷题和错词专项中练习。")
        }
        .sheet(item: $immediateQuestionRequest) { request in
            PersonalQuestionEditor(relatedWordIDs: [request.id])
        }
    }
    private var questionPromptTitle: String {
        guard let id = savedWordAwaitingQuestion, let word = dataManager.word(for: id) else { return "词条已保存" }
        return "“\(word.word)”已保存，要立即添加题目吗？"
    }
    private func savedNewWord(_ id: UUID) {
        selectSavedWord(id)
        savedWordAwaitingQuestion = id
    }
    private func selectSavedWord(_ id: UUID) {
        search = ""; category = "全部分类"; status = "全部状态"
        personalOnly = false; personalArchived = false; showArchived = true
        selectedWordID = id
    }
}
struct WordRowView: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word
    let errorActivityDate: Date?

    init(word: Word, errorActivityDate: Date? = nil) {
        self.word = word
        self.errorActivityDate = errorActivityDate
    }

    private var record: StudyRecord { dataManager.getStudyRecord(for: word.id) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(word.word).font(.title3.weight(.semibold))
                    if record.isFavorite { Image(systemName: "star.fill").foregroundColor(.orange).font(.caption) }
                    if word.sourceDeleted { Text("原资料删除").font(.caption2).foregroundColor(.secondary) }
                    if word.isPersonal { Text(dataManager.archivedWordIDs.contains(word.id) ? "已归档" : "手动添加").font(.caption2).foregroundColor(.secondary) }
                }
                Text(word.meanings.first ?? "").font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                Text(word.category + (word.subcategory.isEmpty ? "" : " · " + word.subcategory)).font(.caption2).foregroundColor(.secondary)
                if let errorActivityDate, errorActivityDate != .distantPast {
                    HStack(spacing: 4) {
                        Text("最近错题").font(.caption2)
                        Text(errorActivityDate, style: .date).font(.caption2)
                    }.foregroundColor(.secondary)
                }
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
    private let initialWord: Word
    private var word: Word { dataManager.word(for: initialWord.id) ?? initialWord }
    init(word: Word) { initialWord = word }
    @State private var localEditorRequest: WordEditorRequest?
    @State private var archiveRequest: PersonalRevision?
    @State private var archiveError = ""
    private var record: StudyRecord { dataManager.getStudyRecord(for: word.id) }
    private var relatedQuestions: [Question] { dataManager.relatedQuestions(for: word.id) }
    private var manuallyAddedQuestionCount: Int {
        relatedQuestions.lazy.filter { $0.personalEntryID != nil }.count
    }
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
                    NoteContentView(value: record.personalNotes)
                }
                Button { openEditor(.notes) } label: {
                    Label(record.personalNotes.isEmpty ? "添加笔记" : "编辑笔记", systemImage: "note.text")
                }
                if record.noteHistory.count > 1 {
                    DisclosureGroup("笔记历史（\(record.noteHistory.count)）") {
                        ForEach(record.noteHistory.reversed()) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.date, style: .date).font(.caption).foregroundColor(.secondary)
                                if event.value.isEmpty { Text("（清空笔记）").font(.subheadline) }
                                else { NoteContentView(value: event.value) }
                            }
                        }
                    }
                }
            }
            WordUsageSections(word: word, record: record, onEditSynonyms: { openEditor(.synonyms) })
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
            Section("关联练习") {
                Text(relatedQuestions.isEmpty ? "暂时没有关联题目，可以手动添加。" : "有 \(relatedQuestions.count) 道使用中的关联题目，可在刷题中练习。")
                    .font(.subheadline).foregroundColor(.secondary)
                if !relatedQuestions.isEmpty {
                    NavigationLink {
                        WordRelatedQuestionsView(word: word)
                    } label: {
                        Label(manuallyAddedQuestionCount > 0 ? "查看关联题目（我添加了 \(manuallyAddedQuestionCount) 道）" : "查看关联题目（\(relatedQuestions.count) 道）",
                              systemImage: "list.bullet.rectangle")
                    }
                }
                Button { openEditor(.addQuestion) } label: { Label("给这个词添加题目", systemImage: "plus.square") }
                    .disabled(dataManager.archivedWordIDs.contains(word.id))
            }
            if word.isPersonal {
                Section("我的词条 · 手动添加") {
                    Text(dataManager.archivedWordIDs.contains(word.id) ? "已归档：不加入新学习和提醒，历史仍保留。" : "这是你手动添加的词条。")
                        .font(.footnote).foregroundColor(.secondary)
                    Button("编辑词条内容") { openEditor(.personalWord) }
                    Button(dataManager.archivedWordIDs.contains(word.id) ? "恢复词条" : "归档词条") {
                        archiveRequest = dataManager.currentRevision(for: word.id)
                    }
                    if !archiveError.isEmpty { Text(archiveError).foregroundColor(.red) }
                }
            } else { Section("原始资料") {
                Text("高频800词.pdf · 第 \(word.sourcePages) 页").font(.subheadline)
                if word.sourceDeleted { Text("原资料标注删除，保留供查阅；默认不加入新词计划。").foregroundColor(.secondary) }
                ForEach(Array(word.occurrences.enumerated()), id: \.offset) { _, occurrence in
                    if !occurrence.correctionNote.isEmpty { Text(occurrence.correctionNote).font(.footnote).foregroundColor(.orange) }
                }
                Button("查看 PDF 原页") { openEditor(.source) }
            } }
        }
        .navigationTitle(word.word).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $localEditorRequest) { WordEditorSheet(request: $0) }
        .confirmationDialog("确认更改词条的归档状态？学习历史会保留。", isPresented: Binding(get: { archiveRequest != nil }, set: { if !$0 { archiveRequest = nil } }), titleVisibility: .visible) {
            if let pending = archiveRequest {
                Button(pending.archived ? "恢复" : "归档") {
                    do { try dataManager.setPersonalArchived(entryID: word.id, expectedHeads: [pending.id], archived: !pending.archived) }
                    catch { archiveError = error.localizedDescription }
                    archiveRequest = nil
                }
            }
            Button("取消", role: .cancel) { archiveRequest = nil }
        }
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
        Section(word.isPersonal ? "释义 · 手动添加" : "释义 · 原资料") {
            ForEach(Array(word.meanings.enumerated()), id: \.offset) { _, meaning in Text(meaning).lineSpacing(6).textSelection(.enabled) }
        }
    }
}
struct WordUsageSections: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word
    /// 当前学习记录里的补充近义词，和内置「关联词辨析」分开显示，互不覆盖。
    var record = StudyRecord()
    var onEditSynonyms: (() -> Void)? = nil
    private var synonyms: [ConfusableWord] { record.personalSynonyms }
    var body: some View {
        if !word.keyPoints.isEmpty { Section(word.isPersonal ? "用法与重点 · 手动添加" : "重点解析 · 原资料用法提示") { Text(word.keyPoints).lineSpacing(6) } }
        if !word.confusableWords.isEmpty {
            Section("关联词与辨析") {
                ForEach(Array(word.confusableWords.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) {
                        if let related = relatedWord(named: item.word, includePersonal: false) {
                            NavigationLink(item.word, destination: WordDetailView(word: related)).font(.headline)
                        } else { Text(item.word).font(.headline) }
                        Text(item.difference).font(.subheadline).foregroundColor(.secondary).lineSpacing(4)
                    }.padding(.vertical, 4)
                }
            }
        }
        Section("近义词 · 我的补充") {
            if synonyms.isEmpty {
                Text(word.confusableWords.isEmpty
                     ? "这个词原资料没有近义词。可以自己补充意思相近的词和区别，只保存在本机记录里。"
                     : "原资料的近义词在上方，这里可以继续补充你自己的。")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                ForEach(Array(synonyms.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) {
                        if let related = relatedWord(named: item.word, includePersonal: true) {
                            NavigationLink(item.word, destination: WordDetailView(word: related)).font(.headline)
                        } else { Text(item.word).font(.headline) }
                        if !item.difference.isEmpty {
                            Text(item.difference).font(.subheadline).foregroundColor(.secondary).lineSpacing(4)
                        }
                    }.padding(.vertical, 4)
                }
            }
            if let onEditSynonyms = onEditSynonyms {
                Button(action: onEditSynonyms) {
                    Label(synonyms.isEmpty ? "添加近义词" : "编辑补充的近义词", systemImage: "text.badge.plus")
                }
            }
            if record.synonymHistory.count > 1 {
                DisclosureGroup("近义词修改历史（\(record.synonymHistory.count)）") {
                    ForEach(record.synonymHistory.reversed()) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.date, style: .date).font(.caption).foregroundColor(.secondary)
                            Text(PersonalSynonyms.displayText(event.value)).font(.subheadline).textSelection(.enabled)
                        }
                    }
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
    /// 内置词优先，避免同名个人词条截获原资料里的关联词。
    private func relatedWord(named name: String, includePersonal: Bool) -> Word? {
        if let builtIn = dataManager.words.first(where: { !$0.isPersonal && $0.word == name }) { return builtIn }
        guard includePersonal else { return nil }
        return dataManager.words.first { $0.word == name }
    }
}
struct WordRelatedQuestionsView: View {
    @EnvironmentObject private var dataManager: DataManager
    let initialWord: Word
    @State private var practiceQueue: [Question] = []
    @State private var showingPractice = false
    private var word: Word { dataManager.word(for: initialWord.id) ?? initialWord }
    init(word: Word) { initialWord = word }
    private var questions: [Question] {
        dataManager.relatedQuestions(for: word.id).sorted { lhs, rhs in
            let leftIsManual = lhs.personalEntryID != nil, rightIsManual = rhs.personalEntryID != nil
            if leftIsManual != rightIsManual { return leftIsManual }
            return lhs.content < rhs.content
        }
    }
    var body: some View {
        let displayedQuestions = questions
        let manuallyAddedCount = displayedQuestions.lazy.filter { $0.personalEntryID != nil }.count
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("共 \(displayedQuestions.count) 道关联题").font(.headline)
                        Text(manuallyAddedCount > 0 ? "其中 \(manuallyAddedCount) 道由你手动添加" : "可先查看题目，也可直接开始作答")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { practiceQueue = displayedQuestions; showingPractice = true } label: {
                        Label("开始作答", systemImage: "play.fill")
                    }.disabled(displayedQuestions.isEmpty)
                }
            }
            Section("题目列表") {
                ForEach(displayedQuestions) { question in
                    NavigationLink(destination: QuestionExplanationView(question: question, selectedAnswer: nil)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.content).lineLimit(3)
                            HStack(spacing: 6) {
                                Text(question.type.rawValue)
                                if question.personalEntryID != nil { Text("我添加的") }
                                if !question.source.isEmpty { Text(question.source).lineLimit(1) }
                            }.font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("\(word.word) · 关联题").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingPractice) { PracticeSessionView(questions: practiceQueue) }
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
                    Button("保存") { if let value = validCount, dataManager.setErrorCount(for: word.id, count: value) { dismiss() } }.disabled(validCount == nil)
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
    @State private var blocks: [NoteBlock] = [.paragraph()]
    @State private var pendingImages: [UUID: Data] = [:]
    @State private var originalValue = ""
    @State private var loadedDraft = false
    @State private var showAlbum = false
    @State private var showCamera = false
    @State private var insertionIndex = 0
    @State private var processingImage = false
    @State private var errorMessage = ""
    @State private var showError = false
    private var draft: RichNote { RichNote(blocks: blocks) }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(blocks.indices, id: \.self) { index in
                        let block = blocks[index]
                        if block.kind == .text {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $blocks[index].text)
                                    .frame(minHeight: 110)
                                    .padding(6)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                HStack {
                                    Button { insertionIndex = index + 1; processingImage = true; showAlbum = true } label: {
                                        Label("相册", systemImage: "photo.on.rectangle")
                                    }
                                    Button { openCamera(after: index) } label: {
                                        Label("拍照", systemImage: "camera")
                                    }
                                    Spacer()
                                    if blocks.count > 1 {
                                        Button(role: .destructive) { blocks.remove(at: index) } label: {
                                            Image(systemName: "trash")
                                        }.accessibilityLabel("删除文字段落")
                                    }
                                }.buttonStyle(.borderless)
                            }
                        } else if let imageID = block.imageID {
                            VStack(alignment: .trailing, spacing: 4) {
                                NoteImageView(imageID: imageID, pending: pendingImages[imageID])
                                Button("删除图片", role: .destructive) {
                                    blocks.remove(at: index)
                                    pendingImages.removeValue(forKey: imageID)
                                }.font(.caption)
                            }
                        }
                    }
                    Button { blocks.append(.paragraph()) } label: { Label("添加文字段落", systemImage: "text.badge.plus") }
                    Text("图片保存在笔记备份中；单张最多 750 KB，整份备份最多 20 MB。")
                        .font(.footnote).foregroundColor(.secondary)
                    if processingImage { ProgressView("正在处理图片…") }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(word.word) · 笔记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(processingImage) }
                }.onAppear {
                    guard !loadedDraft else { return }
                    originalValue = dataManager.getStudyRecord(for: word.id).personalNotes
                    blocks = RichNote.decode(originalValue)?.blocks ?? [.paragraph()]
                    if blocks.isEmpty { blocks = [.paragraph()] }
                    loadedDraft = true
                }
                .sheet(isPresented: $showAlbum) {
                    NoteAlbumPicker(isPresented: $showAlbum) { image, attempted in
                        handlePickedImage(image, attempted: attempted)
                    }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    NoteCameraPicker(isPresented: $showCamera) { image, attempted in
                        handlePickedImage(image, attempted: attempted)
                    }
                        .ignoresSafeArea()
                }
                .alert("笔记未能完成", isPresented: $showError) {
                    Button("继续编辑", role: .cancel) { }
                } message: { Text(errorMessage) }
        }.navigationViewStyle(.stack)
    }
    private func openCamera(after index: Int) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            fail("此设备没有可用相机。")
            return
        }
        insertionIndex = index + 1
        processingImage = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    if allowed { showCamera = true }
                    else { processingImage = false; fail("没有相机权限。请在系统设置中允许本 App 使用相机。") }
                }
            }
        case .denied, .restricted:
            processingImage = false
            fail("没有相机权限。请在系统设置中允许本 App 使用相机。")
        @unknown default:
            processingImage = false
            fail("无法检查相机权限。")
        }
    }
    private func handlePickedImage(_ image: UIImage?, attempted: Bool) {
        guard let image = image else {
            processingImage = false
            if attempted { fail("无法读取所选图片，请重试。") }
            return
        }
        processingImage = true
        DispatchQueue.global(qos: .userInitiated).async {
            let data = NoteImageCompressor.compress(image)
            DispatchQueue.main.async {
                processingImage = false
                guard let data = data else { fail("图片处理失败或压缩后仍超过 750 KB，请换一张图片。") ; return }
                let imageID = UUID()
                pendingImages[imageID] = data
                let position = min(insertionIndex, blocks.count)
                blocks.insert(.image(imageID), at: position)
                blocks.insert(.paragraph(), at: position + 1)
            }
        }
    }
    private func save() {
        do {
            try dataManager.updateRichNote(for: word.id, note: draft, newImages: pendingImages, expectedValue: originalValue)
            dismiss()
        } catch { fail(error.localizedDescription) }
    }
    private func fail(_ message: String) { errorMessage = message; showError = true }
}

private struct NoteContentView: View {
    let value: String
    var body: some View {
        if let note = RichNote.decode(value) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(note.blocks) { block in
                    if block.kind == .text, !block.text.isEmpty {
                        Text(block.text).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if let imageID = block.imageID {
                        NoteImageView(imageID: imageID, pending: nil)
                    }
                }
            }
        } else { Text("笔记格式无法读取").foregroundColor(.red) }
    }
}

private struct NoteImageView: View {
    @EnvironmentObject private var dataManager: DataManager
    let imageID: UUID
    let pending: Data?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 700, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("笔记图片")
            } else {
                Label("图片无法读取", systemImage: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { load() }
        .onChange(of: imageID) { _ in load() }
    }
    private func load() {
        image = (pending ?? dataManager.noteImageData(for: imageID)).flatMap(UIImage.init(data:))
    }
}

private struct NoteAlbumPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let picked: (UIImage?, Bool) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, picked: picked) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var isPresented: Bool
        let picked: (UIImage?, Bool) -> Void
        init(isPresented: Binding<Bool>, picked: @escaping (UIImage?, Bool) -> Void) {
            _isPresented = isPresented; self.picked = picked
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented = false
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { picked(nil, false); return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async { self.picked(object as? UIImage, true) }
            }
        }
    }
}

private struct NoteCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let picked: (UIImage?, Bool) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, picked: picked) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var isPresented: Bool
        let picked: (UIImage?, Bool) -> Void
        init(isPresented: Binding<Bool>, picked: @escaping (UIImage?, Bool) -> Void) {
            _isPresented = isPresented; self.picked = picked
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            isPresented = false
            picker.dismiss(animated: true) { self.picked(image, true) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented = false; picker.dismiss(animated: true) { self.picked(nil, false) }
        }
    }
}

private enum NoteImageCompressor {
    static func compress(_ image: UIImage) -> Data? {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return nil }
        for edge in [CGFloat(1280), 1024, 800, 640] {
            let scale = min(1, edge / max(width, height))
            let size = CGSize(width: max(1, width * scale), height: max(1, height * scale))
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            for quality in [CGFloat(0.72), 0.60, 0.48] {
                if let data = resized.jpegData(compressionQuality: quality), data.count <= 750_000 { return data }
            }
        }
        return nil
    }
}

struct SynonymEditorView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let word: Word
    @State private var items: [ConfusableWord] = []
    @State private var name = ""
    @State private var difference = ""
    @State private var editingIndex: Int?
    @State private var errorMessage = ""
    @State private var loadedDraft = false
    private var trimmedName: String { PersonalLibrary.trimmed(name) }
    private var repeatsBuiltIn: Bool {
        let key = PersonalLibrary.normalizedName(trimmedName)
        return !key.isEmpty && word.confusableWords.contains { PersonalLibrary.normalizedName($0.word) == key }
    }
    var body: some View {
        NavigationView {
            Form {
                Section("近义词") {
                    TextField("例如：一脉相传", text: $name)
                    if repeatsBuiltIn {
                        Text("原资料的关联词里已经有这个词；保存后会保留你的区别说明，原内容不变。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                Section("区别说明（可留空）") {
                    TextEditor(text: $difference).frame(minHeight: 90)
                }
                Section {
                    Button(editingIndex == nil ? "添加到列表" : "更新这一条") { _ = stage() }
                        .disabled(trimmedName.isEmpty)
                    if editingIndex != nil { Button("取消编辑这一条") { resetFields() } }
                    if !errorMessage.isEmpty { Text(errorMessage).foregroundColor(.red) }
                }
                if !items.isEmpty {
                    Section("已补充 \(items.count) 条") {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            Button { load(index) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(item.word).foregroundColor(.primary)
                                        if editingIndex == index { Image(systemName: "pencil").font(.caption).foregroundColor(AppStyle.accent) }
                                        Spacer()
                                    }
                                    if !item.difference.isEmpty {
                                        Text(item.difference).font(.caption).foregroundColor(.secondary).lineLimit(3)
                                    }
                                }
                            }
                        }.onDelete(perform: remove)
                    }
                }
                Section {
                    Text("近义词按词条保存在本机学习记录里，会随备份和附近同步一起传到另一台设备；修改历史不会被删除。原资料的关联词辨析始终按原文显示。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("\(word.word) · 近义词").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear {
                guard !loadedDraft else { return }
                items = dataManager.getStudyRecord(for: word.id).personalSynonyms
                loadedDraft = true
            }
        }.navigationViewStyle(.stack)
    }
    @discardableResult private func stage() -> Bool {
        let entry = ConfusableWord(word: trimmedName, difference: PersonalLibrary.trimmed(difference))
        guard !entry.word.isEmpty else { errorMessage = "请填写近义词。"; return false }
        guard entry.word.count <= PersonalSynonyms.maximumNameLength else {
            errorMessage = "近义词最多 \(PersonalSynonyms.maximumNameLength) 个字。"; return false
        }
        guard entry.difference.count <= PersonalSynonyms.maximumDifferenceLength else {
            errorMessage = "区别说明超过长度限制，请精简后再保存。"; return false
        }
        guard PersonalLibrary.normalizedName(entry.word) != PersonalLibrary.normalizedName(word.word) else {
            errorMessage = "“\(word.word)”是词条本身，不能作为它的近义词。"; return false
        }
        var value = items
        if let editing = editingIndex, value.indices.contains(editing) { value.remove(at: editing) }
        let key = PersonalLibrary.normalizedName(entry.word)
        if let index = value.firstIndex(where: { PersonalLibrary.normalizedName($0.word) == key }) { value[index] = entry }
        else { value.append(entry) }
        guard value.count <= PersonalSynonyms.maximumEntries else {
            errorMessage = "最多补充 \(PersonalSynonyms.maximumEntries) 条近义词。"; return false
        }
        items = value; errorMessage = ""; resetFields()
        return true
    }
    private func load(_ index: Int) {
        guard items.indices.contains(index) else { return }
        name = items[index].word; difference = items[index].difference
        editingIndex = index; errorMessage = ""
    }
    private func remove(_ offsets: IndexSet) {
        items.remove(atOffsets: offsets); errorMessage = ""; resetFields()
    }
    private func resetFields() { name = ""; difference = ""; editingIndex = nil }
    private func save() {
        // 直接点保存时，把还没加入列表的那一条一起写入，避免输入内容被静默丢掉。
        if !trimmedName.isEmpty, !stage() { return }
        do { try dataManager.updateSynonyms(for: word.id, synonyms: items); dismiss() }
        catch { errorMessage = error.localizedDescription }
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
    @State private var pendingRating: Int?
    @State private var relatedPracticeQueue: [Question] = []
    @State private var showingRelatedPractice = false
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
                                    if title.contains("巩固") {
                                        StudyRelatedQuestionsCard(word: word, questions: dataManager.relatedQuestions(for: word.id)) { questions in
                                            relatedPracticeQueue = questions
                                            showingRelatedPractice = true
                                        }
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
        .fullScreenCover(isPresented: $showingRelatedPractice) { PracticeSessionView(questions: relatedPracticeQueue) }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if title != "提醒巩固", let saved = UserDefaults.standard.dictionary(forKey: sessionKey),
               let ids = saved["ids"] as? [String], let progress = saved["index"] as? Int, progress >= 0, progress < ids.count {
                let restored = ids.compactMap { UUID(uuidString: $0) }.compactMap { dataManager.activeWord(for: $0) }
                if restored.count == ids.count { queue = restored; index = progress } else { queue = words }
            } else { queue = words }
            saveProgress()
        }
        .onDisappear { speaker.stop() }
    }
    private func ratingButton(_ title: String, hint: String, rating: Int, color: Color) -> some View {
        Button {
            guard pendingRating == nil, let word = current else { return }
            pendingRating = rating
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { @MainActor in
                // Let SwiftUI draw the pressed/saving state before persistence work starts.
                await Task.yield()
                guard dataManager.rate(word.id, rating: rating) else { pendingRating = nil; return }
                speaker.stop()
                withAnimation(.easeOut(duration: 0.16)) { index += 1; revealed = false }
                saveProgress(); pendingRating = nil
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if pendingRating == rating { ProgressView().scaleEffect(0.75).tint(color) }
                    Text(pendingRating == rating ? "正在记录" : title).font(.headline)
                }
                Text(hint).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundColor(color)
        }
        .buttonStyle(StudyRatingButtonStyle(color: color))
        .disabled(pendingRating != nil)
        .accessibilityHint("记录本次掌握情况并进入下一个词")
    }
    private func saveProgress() {
        if index >= queue.count { UserDefaults.standard.removeObject(forKey: sessionKey) }
        else { UserDefaults.standard.set(["ids": queue.map { $0.id.uuidString }, "index": index], forKey: sessionKey) }
    }
}
private struct StudyRelatedQuestionsCard: View {
    let word: Word
    let questions: [Question]
    let startPractice: ([Question]) -> Void
    var body: some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("题目巩固", systemImage: "pencil.and.list.clipboard")
                        .font(.headline).foregroundColor(AppStyle.accent)
                    Spacer()
                    Text("关联 \(questions.count) 道").font(.caption).foregroundColor(.secondary)
                }
                Text("用题目中的语境确认刚刚看到的释义；作答后才显示答案和解析。")
                    .font(.caption).foregroundColor(.secondary)
                Text(questions[0].content).font(.subheadline).lineLimit(3)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill)).cornerRadius(10)
                Button { startPractice(questions) } label: {
                    Label("开始关联题巩固", systemImage: "play.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                NavigationLink("查看全部关联题", destination: WordRelatedQuestionsView(word: word))
                    .font(.subheadline)
            }
            .padding(16)
            .background(AppStyle.accent.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppStyle.accent.opacity(0.18)))
            .cornerRadius(16)
        }
    }
}
private struct StudyRatingButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.22 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(configuration.isPressed ? 0.55 : 0.16), lineWidth: configuration.isPressed ? 2 : 1)
            )
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
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
