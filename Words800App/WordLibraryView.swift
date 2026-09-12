import SwiftUI

// MARK: - Word Library View
struct WordLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedCategory = "全部"

    var filteredWords: [Word] {
        var words = dataManager.words

        if selectedCategory != "全部" {
            words = words.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            words = dataManager.searchWords(keyword: searchText).filter { word in
                selectedCategory == "全部" || word.category == selectedCategory
            }
        }

        return words
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        CategoryButton(title: "全部", isSelected: selectedCategory == "全部") {
                            selectedCategory = "全部"
                        }

                        ForEach(dataManager.categories, id: \.self) { category in
                            CategoryButton(title: category, isSelected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGray6))

                // Word List
                List(filteredWords) { word in
                    NavigationLink(destination: WordDetailView(word: word)) {
                        WordRowView(word: word)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("词库")
            .searchable(text: $searchText, prompt: "搜索词语、释义...")
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .cornerRadius(20)
        }
    }
}

struct WordRowView: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word

    var studyRecord: StudyRecord {
        dataManager.getStudyRecord(for: word.id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(word.word)
                        .font(.headline)

                    if studyRecord.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Text(word.pinyin)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(word.meanings.first ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Circle()
                    .fill(studyRecord.masteryLevel.color)
                    .frame(width: 10, height: 10)

                if studyRecord.errorCount > 0 {
                    Text("错\(studyRecord.errorCount)次")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Word Detail View
struct WordDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word
    @State private var studyRecord: StudyRecord
    @State private var showingNotesEditor = false

    init(word: Word) {
        self.word = word
        _studyRecord = State(initialValue: DataManager.shared.getStudyRecord(for: word.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(word.word)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: {
                            dataManager.toggleFavorite(for: word.id)
                            studyRecord = dataManager.getStudyRecord(for: word.id)
                        }) {
                            Image(systemName: studyRecord.isFavorite ? "star.fill" : "star")
                                .foregroundColor(.orange)
                                .font(.title2)
                        }
                    }

                    Text(word.pinyin)
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text(word.category)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Meanings
                VStack(alignment: .leading, spacing: 10) {
                    Text("释义")
                        .font(.headline)

                    ForEach(Array(word.meanings.enumerated()), id: \.offset) { index, meaning in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                            Text(meaning)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Key Points
                VStack(alignment: .leading, spacing: 10) {
                    Text("重点解析")
                        .font(.headline)

                    Text(word.keyPoints)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Confusable Words
                if !word.confusableWords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("易混词辨析")
                            .font(.headline)

                        ForEach(word.confusableWords, id: \.self) { confusable in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("vs \(confusable.word)")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                Text(confusable.difference)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Examples
                if !word.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("例句")
                            .font(.headline)

                        ForEach(word.examples, id: \.self) { example in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(example.sentence)
                                    .foregroundColor(.primary)
                                Text(example.translation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Study Status
                VStack(alignment: .leading, spacing: 10) {
                    Text("学习状态")
                        .font(.headline)

                    // Mastery Level
                    HStack {
                        Text("掌握程度")
                            .foregroundColor(.secondary)
                        Spacer()
                        Menu {
                            ForEach(MasteryLevel.allCases, id: \.self) { level in
                                Button(action: {
                                    dataManager.updateMasteryLevel(for: word.id, level: level)
                                    studyRecord = dataManager.getStudyRecord(for: word.id)
                                }) {
                                    HStack {
                                        Text(level.rawValue)
                                        if level == studyRecord.masteryLevel {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(studyRecord.masteryLevel.rawValue)
                                    .foregroundColor(studyRecord.masteryLevel.color)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("错误次数")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(studyRecord.errorCount)次")
                            .foregroundColor(studyRecord.errorCount > 0 ? .red : .green)
                    }

                    if !studyRecord.errorHistory.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 5) {
                            Text("错题记录")
                                .foregroundColor(.secondary)

                            ForEach(studyRecord.errorHistory.prefix(3)) { error in
                                Text("• \(error.context)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if studyRecord.errorHistory.count > 3 {
                                Text("还有\(studyRecord.errorHistory.count - 3)条记录...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Personal Notes
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("个人笔记")
                            .font(.headline)

                        Spacer()

                        Button("编辑") {
                            showingNotesEditor = true
                        }
                        .font(.subheadline)
                    }

                    if studyRecord.personalNotes.isEmpty {
                        Text("暂无笔记，点击编辑添加")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Text(studyRecord.personalNotes)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(wordId: word.id, notes: studyRecord.personalNotes) { newNotes in
                dataManager.updateNotes(for: word.id, notes: newNotes)
                studyRecord = dataManager.getStudyRecord(for: word.id)
            }
        }
    }
}

struct NotesEditorView: View {
    let wordId: UUID
    @State private var notes: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss

    init(wordId: UUID, notes: String, onSave: @escaping (String) -> Void) {
        self.wordId = wordId
        _notes = State(initialValue: notes)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $notes)
                    .padding()
            }
            .navigationTitle("编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(notes)
                        dismiss()
                    }
                }
            }
        }
    }
}
