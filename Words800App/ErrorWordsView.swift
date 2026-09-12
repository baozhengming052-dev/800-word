import SwiftUI

struct ErrorWordsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var sort: WordSort = .errors
    @State private var hideMastered = false
    @State private var editWord: Word?
    @State private var cards = false
    @State private var practice = false
    @State private var selectedQuestions: [Question] = []
    private var words: [Word] {
        dataManager.sorted(dataManager.errorWords.filter { !hideMastered || dataManager.getStudyRecord(for: $0.id).masteryLevel != .mastered }, by: sort)
    }
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Button { cards = true } label: { Label("词卡巩固", systemImage: "rectangle.on.rectangle") }.disabled(words.isEmpty)
                        Spacer()
                        Button {
                            let visible = Set(words.map { $0.word })
                            selectedQuestions = Array(dataManager.practiceQuestions(type: "全部题型", category: "全部分类", errorsOnly: true, limit: dataManager.questions.count, includeArchived: true)
                                .filter { $0.relatedWords.contains(where: visible.contains) }.prefix(20))
                            if selectedQuestions.isEmpty { dataManager.message = "暂时没有关联题目，请先用词卡巩固。" } else { practice = true }
                        } label: { Label("专项刷题", systemImage: "pencil") }.disabled(words.isEmpty)
                    }.buttonStyle(.borderless)
                    Picker("排序", selection: $sort) {
                        Text("错误次数最多").tag(WordSort.errors)
                        Text("最近学习").tag(WordSort.recent)
                    }
                    Toggle("隐藏已掌握词", isOn: $hideMastered)
                }
                Section("\(words.count) 个错词 · 点右侧编辑按钮可修改") {
                    ForEach(words) { word in
                        HStack {
                            NavigationLink(destination: WordDetailView(word: word)) { WordRowView(word: word) }
                            Button { editWord = word } label: { Image(systemName: "square.and.pencil") }
                                .buttonStyle(.borderless).accessibilityLabel("编辑\(word.word)错误次数")
                        }
                    }
                    if words.isEmpty {
                        Text("这里会收集答错或选择“忘记”的词。你也可以在词条详情中手动录入错误次数。")
                            .foregroundColor(.secondary).padding(.vertical)
                    }
                }
            }
            .navigationTitle("错词本")
            .sheet(item: $editWord) { ErrorCountEditor(word: $0) }
            .sheet(isPresented: $cards) { StudySessionView(title: "巩固薄弱词", words: Array(words.prefix(20))) }
            .fullScreenCover(isPresented: $practice) { PracticeSessionView(questions: selectedQuestions) }
        }.navigationViewStyle(.stack)
    }
}
