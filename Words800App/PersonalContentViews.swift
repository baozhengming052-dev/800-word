import SwiftUI

struct PersonalWordEditor: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let editing: Bool
    let onSaved: (UUID) -> Void
    let onUseExisting: ((UUID) -> Void)?
    @State private var entryID: UUID
    @State private var content = PersonalWordContent()
    @State private var original = PersonalWordContent()
    @State private var notes = ""
    @State private var expectedHeads: Set<UUID> = []
    @State private var loaded = false
    @State private var completed = false
    @State private var errorMessage = ""
    @State private var confirmDiscard = false
    @State private var pendingExistingID: UUID?

    init(wordID: UUID? = nil, onSaved: @escaping (UUID) -> Void = { _ in }, onUseExisting: ((UUID) -> Void)? = nil) {
        editing = wordID != nil; self.onSaved = onSaved; self.onUseExisting = onUseExisting
        _entryID = State(initialValue: wordID ?? UUID())
    }
    private var dirty: Bool { content != original || !notes.isEmpty }
    private var matches: [Word] { dataManager.matchingWords(content.word, excluding: entryID) }
    var body: some View {
        NavigationView {
            Form {
                Section("词条 · 手动添加") {
                    TextField("词语（必填，最多 80 字）", text: $content.word)
                    PersonalTextField(title: "释义（必填）", text: $content.meaning, limit: 10_000)
                    TextField("拼音（可选，最多 100 字）", text: $content.pinyin)
                    TextField("分类（可选，最多 100 字）", text: $content.category)
                    Text("不填分类时归入“自建词”。保存会去掉内容字段首尾空白。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                if !matches.isEmpty {
                    Section("已有同名词条") {
                        Text("可以打开已有词条补充笔记、添加题目，无需重复创建。")
                            .font(.footnote).foregroundColor(.secondary)
                        ForEach(matches) { word in
                            NavigationLink("打开已有：\(word.word)", destination: WordDetailView(word: word))
                            if onUseExisting != nil {
                                Button("使用这个已有词条") {
                                    guard !completed else { return }
                                    if dirty { pendingExistingID = word.id; confirmDiscard = true }
                                    else { useExisting(word.id) }
                                }
                            }
                        }
                    }
                }
                Section("补充内容（可选）") {
                    PersonalTextField(title: "例句", text: $content.example, limit: 10_000)
                    PersonalTextField(title: "用法与重点", text: $content.keyPoints, limit: 10_000)
                    if !editing {
                        Text("个人笔记（可选；格式原样保留，最多 100,000 UTF-8 字节）").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $notes).frame(minHeight: 100)
                        Text("\(notes.utf8.count) / 100,000 字节").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundColor(.red).textSelection(.enabled) } }
                Section {
                    Text("只保存手动录入的内容，不修改原 PDF。归档词条的编辑仍保留归档状态；恢复时会检查同名词。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(editing ? "编辑我的词条" : "添加词条").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { pendingExistingID = nil; if dirty { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!loaded || completed) }
            }
            .onAppear { load() }
            .confirmationDialog("放弃尚未保存的词条修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(pendingExistingID == nil ? "放弃修改" : "放弃草稿并使用已有词条", role: .destructive) {
                    if let id = pendingExistingID { useExisting(id) }
                    else { dismiss() }
                }
                Button("继续编辑", role: .cancel) { pendingExistingID = nil }
            }
        }
        .navigationViewStyle(.stack).tint(AppStyle.accent)
        .interactiveDismissDisabled(dirty && !completed)
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if editing {
            guard let revision = dataManager.currentRevision(for: entryID), let word = revision.word else {
                errorMessage = "词条已不可用，请取消后重新打开。"; completed = true; return
            }
            content = word; original = word
            expectedHeads = dataManager.expectedHeads(for: entryID)
        }
    }
    private func save() {
        guard loaded, !completed else { return }
        do {
            try dataManager.savePersonalWord(content: content, wordID: entryID, expectedHeads: expectedHeads,
                notes: editing || notes.isEmpty ? nil : notes)
            completed = true; onSaved(entryID); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    private func useExisting(_ id: UUID) {
        guard !completed, let use = onUseExisting else { return }
        completed = true; use(id); dismiss()
    }
}

struct PersonalTextField: View {
    let title: String
    @Binding var text: String
    let limit: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline)
            TextEditor(text: $text).frame(minHeight: 90).accessibilityLabel(title)
            Text("\(text.count) / \(limit) 字").font(.caption2).foregroundColor(text.count > limit ? .red : .secondary)
        }
    }
}

struct PersonalQuestionEditor: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let editing: Bool
    @State private var entryID: UUID
    @State private var content: PersonalQuestionContent
    @State private var original: PersonalQuestionContent
    @State private var expectedHeads: Set<UUID> = []
    @State private var loaded = false
    @State private var completed = false
    @State private var errorMessage = ""
    @State private var confirmDiscard = false
    @State private var addingWord = false

    init(entryID: UUID? = nil, relatedWordIDs: [UUID] = []) {
        editing = entryID != nil
        _entryID = State(initialValue: entryID ?? UUID())
        let initial = PersonalQuestionContent(relatedWordIDs: relatedWordIDs)
        _content = State(initialValue: initial); _original = State(initialValue: initial)
    }
    private var dirty: Bool { content != original }
    var body: some View {
        NavigationView {
            Form {
                Section("题目 · 手动录入") {
                    PersonalTextField(title: "题干（必填）", text: $content.content, limit: 10_000)
                    Text("手动录入不代表已核验的考试真题。请自行核对答案和出处。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("四个选项（必填，内容不能重复）") {
                    ForEach(0..<4, id: \.self) { index in
                        PersonalTextField(title: "选项 \(["A", "B", "C", "D"][index])", text: $content.options[index], limit: 2_000)
                    }
                    Picker("正确答案（必须明确选择）", selection: $content.correctAnswer) {
                        Text("请选择").tag(-1)
                        ForEach(0..<4, id: \.self) { Text(["A", "B", "C", "D"][$0]).tag($0) }
                    }
                }
                Section("解析与出处") {
                    PersonalTextField(title: "解析（必填）", text: $content.explanation, limit: 10_000)
                    PersonalTextField(title: "来源备注（可选）", text: $content.source, limit: 10_000)
                }
                Section("关联词条（至少一个）") {
                    ForEach(content.relatedWordIDs, id: \.self) { id in
                        HStack {
                            Text(dataManager.word(for: id)?.word ?? "词条已不可用")
                            if dataManager.archivedWordIDs.contains(id) { Text("已归档，请移除或先恢复").font(.caption).foregroundColor(.orange) }
                            Spacer()
                            Button("移除") { content.relatedWordIDs.removeAll { $0 == id } }.buttonStyle(.borderless)
                        }
                    }
                    NavigationLink {
                        PersonalWordSelection(selectedIDs: $content.relatedWordIDs, addWord: { addingWord = true })
                    } label: { Label("搜索并选择词条", systemImage: "magnifyingglass") }
                    Button { addingWord = true } label: { Label("先添加一个新词", systemImage: "plus") }
                    Text("新词会单独保存。之后取消题目时，已保存的新词仍留在词库中。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundColor(.red).textSelection(.enabled) } }
                Section {
                    Text("保存修改会产生新版本。已经提交的答案和正在进行的练习仍按原题目版本计分。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity).background(Color(.systemGroupedBackground))
            .navigationTitle(editing ? "编辑我的题目" : "添加题目").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!loaded || completed) }
            }
            .onAppear { load() }
            .confirmationDialog("放弃尚未保存的题目修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) { }
            }
        }
        .navigationViewStyle(.stack).tint(AppStyle.accent)
        .interactiveDismissDisabled(dirty && !completed)
        // This owner survives selection navigation and iPad rotation.
        .sheet(isPresented: $addingWord) {
            PersonalWordEditor(onSaved: selectWord, onUseExisting: selectWord)
        }
    }
    private func selectWord(_ id: UUID) {
        if !content.relatedWordIDs.contains(id) { content.relatedWordIDs.append(id) }
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if editing {
            guard let revision = dataManager.currentRevision(for: entryID), let question = revision.question else {
                errorMessage = "题目已不可用，请取消后重新打开。"; completed = true; return
            }
            content = question; original = question
            expectedHeads = dataManager.expectedHeads(for: entryID)
        }
    }
    private func save() {
        guard loaded, !completed else { return }
        do {
            try dataManager.savePersonalQuestion(content: content, entryID: entryID, expectedHeads: expectedHeads)
            completed = true; dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct PersonalWordSelection: View {
    @EnvironmentObject private var dataManager: DataManager
    @Binding var selectedIDs: [UUID]
    let addWord: () -> Void
    @State private var search = ""
    var body: some View {
        List {
            Button(action: addWord) { Label("添加新词并关联", systemImage: "plus") }
            ForEach(dataManager.searchWords(keyword: search)) { word in
                Button {
                    if selectedIDs.contains(word.id) { selectedIDs.removeAll { $0 == word.id } }
                    else { selectedIDs.append(word.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(word.word)
                            Text(word.meanings.first ?? "").font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if selectedIDs.contains(word.id) { Image(systemName: "checkmark.circle.fill") }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索词语或释义")
        .navigationTitle("选择关联词 · \(selectedIDs.count)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PersonalQuestionManager: View {
    @EnvironmentObject private var dataManager: DataManager
    @State private var archived = false
    @State private var adding = false
    private var entries: [PersonalRevision] {
        dataManager.personalHeads.values.compactMap(\.last)
            .filter { $0.question != nil && $0.archived == archived }
            .sorted { $0.timestamp > $1.timestamp }
    }
    var body: some View {
        List {
            Picker("显示", selection: $archived) { Text("使用中").tag(false); Text("已归档").tag(true) }.pickerStyle(.segmented)
            if entries.isEmpty { Text(archived ? "没有已归档题目。" : "还没有手动题目。点右上角添加。").foregroundColor(.secondary) }
            ForEach(entries) { revision in
                NavigationLink(destination: PersonalQuestionDetail(entryID: revision.entryID)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(revision.question?.content ?? "").lineLimit(3)
                        Text("手动录入 · \(archived ? "已归档" : "使用中")").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("我的题目")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Label("添加题目", systemImage: "plus") } } }
        .sheet(isPresented: $adding) { PersonalQuestionEditor() }
    }
}

struct PersonalQuestionDetail: View {
    @EnvironmentObject private var dataManager: DataManager
    let entryID: UUID
    @State private var editing = false
    @State private var archiveRequest: PersonalRevision?
    @State private var errorMessage = ""
    private var revision: PersonalRevision? { dataManager.currentRevision(for: entryID) }
    var body: some View {
        List {
            if let revision = revision, let content = revision.question {
                Section("手动录入 · \(revision.archived ? "已归档" : "使用中")") {
                    PersonalPayloadView(word: nil, question: content, archived: revision.archived)
                }
                Section {
                    Button("编辑题目") { editing = true }
                    Button(revision.archived ? "恢复题目" : "归档题目") { archiveRequest = revision }
                    Text("归档只停止新练习选取，历史答案和解析一直保留。").font(.footnote).foregroundColor(.secondary)
                }
            }
            if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundColor(.red) } }
        }
        .navigationTitle("题目详情").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { PersonalQuestionEditor(entryID: entryID) }
        .confirmationDialog("确认更改题目的归档状态？", isPresented: Binding(get: { archiveRequest != nil }, set: { if !$0 { archiveRequest = nil } }), titleVisibility: .visible) {
            if let pending = archiveRequest {
                Button(pending.archived ? "恢复" : "归档") {
                    do { try dataManager.setPersonalArchived(entryID: entryID, expectedHeads: [pending.id], archived: !pending.archived) }
                    catch { errorMessage = error.localizedDescription }
                    archiveRequest = nil
                }
            }
            Button("取消", role: .cancel) { archiveRequest = nil }
        }
    }
}

/// Complete content shown only in management/conflict review, never before a practice answer.
struct PersonalPayloadView: View {
    @EnvironmentObject private var dataManager: DataManager
    let word: PersonalWordContent?
    let question: PersonalQuestionContent?
    let archived: Bool
    var wordNames: [UUID: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(archived ? "状态：已归档" : "状态：使用中").font(.caption).foregroundColor(.secondary)
            if let word = word {
                Text(word.word).font(.headline)
                Text("释义：\(word.meaning)")
                Text("拼音：\(word.pinyin.isEmpty ? "未填写" : word.pinyin)")
                Text("分类：\(word.category.isEmpty ? "自建词" : word.category)")
                Text("例句：\(word.example.isEmpty ? "未填写" : word.example)")
                Text("重点：\(word.keyPoints.isEmpty ? "未填写" : word.keyPoints)")
            }
            if let question = question {
                Text(question.content).font(.headline)
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in Text("\(["A", "B", "C", "D"][index]). \(option)") }
                Text("正确答案：\(["A", "B", "C", "D"][question.correctAnswer])")
                Text("解析：\(question.explanation)")
                Text("来源：\(question.source.isEmpty ? "手动录入" : question.source)")
                Text("关联词条")
                ForEach(question.relatedWordIDs, id: \.self) { id in
                    Text((wordNames[id] ?? dataManager.word(for: id)?.word ?? "待导入词条") + " · " + id.uuidString).font(.caption)
                }
            }
        }.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
}
