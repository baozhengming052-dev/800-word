import SwiftUI

struct ErrorWordsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var sort: ErrorWordSort = .errors
    @State private var hideMastered = false
    @State private var editWord: Word?
    @State private var cards = false
    @State private var practice = false
    @State private var selectedQuestions: [Question] = []
    @State private var selectedWordID: UUID?
    private var words: [Word] {
        dataManager.errorWords(sortedBy: sort).filter {
            !hideMastered || dataManager.getStudyRecord(for: $0.id).masteryLevel != .mastered
        }
    }
    var body: some View {
        let displayedWords = words
        AdaptiveWordBrowser(title: "错词本", words: displayedWords, selection: $selectedWordID) { wide, compactDetail in
            sidebar(displayedWords: displayedWords, wide: wide, compactDetail: compactDetail)
        }
    }

    private func sidebar(displayedWords: [Word], wide: Bool, compactDetail: Binding<Bool>) -> some View {
        List {
            controlsSection(displayedWords: displayedWords)
            wordsSection(displayedWords: displayedWords, wide: wide, compactDetail: compactDetail)
        }
        .sheet(item: $editWord) { ErrorCountEditor(word: $0) }
        .sheet(isPresented: $cards) { StudySessionView(title: "巩固薄弱词", words: Array(displayedWords.prefix(20))) }
        .fullScreenCover(isPresented: $practice) { PracticeSessionView(questions: selectedQuestions) }
    }

    private func controlsSection(displayedWords: [Word]) -> some View {
        Section {
            HStack {
                Button { cards = true } label: { Label("词卡巩固", systemImage: "rectangle.on.rectangle") }
                    .disabled(displayedWords.isEmpty)
                Spacer()
                Button { beginPractice(with: displayedWords) } label: { Label("专项刷题", systemImage: "pencil") }
                    .disabled(displayedWords.isEmpty)
            }
            .buttonStyle(.borderless)
            Picker("排序", selection: $sort) {
                ForEach(ErrorWordSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("隐藏已掌握词", isOn: $hideMastered)
        }
    }

    private func wordsSection(displayedWords: [Word], wide: Bool, compactDetail: Binding<Bool>) -> some View {
        Section("\(displayedWords.count) 个错词 · 点右侧编辑按钮可修改") {
            ForEach(displayedWords) { word in
                wordRow(word: word, wide: wide, compactDetail: compactDetail)
            }
            if displayedWords.isEmpty {
                Text("这里会收集答错或选择“忘记”的词。你也可以在词条详情中手动录入错误次数。")
                    .foregroundColor(.secondary).padding(.vertical)
            }
        }
    }

    private func wordRow(word: Word, wide: Bool, compactDetail: Binding<Bool>) -> some View {
        HStack {
            AdaptiveWordLink(
                word: word,
                errorActivityDate: dataManager.getStudyRecord(for: word.id).lastErrorDate,
                isWide: wide,
                selection: $selectedWordID,
                compactDetailPresented: compactDetail
            )
            Button { editWord = word } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑\(word.word)错误次数")
        }
        .listRowBackground(
            wide && selectedWordID == word.id
                ? AppStyle.accent.opacity(0.10)
                : Color(.secondarySystemGroupedBackground)
        )
    }

    private func beginPractice(with displayedWords: [Word]) {
        let visibleWordIDs = Set(displayedWords.map(\.id))
        let candidates = dataManager.practiceQuestions(
            type: "全部题型",
            category: "全部分类",
            errorsOnly: true,
            limit: dataManager.activeQuestions.count,
            includeArchived: true
        )
        let related = candidates.filter { question in
            dataManager.relatedWordIDs(for: question).contains(where: visibleWordIDs.contains)
        }
        selectedQuestions = Array(related.prefix(20))
        if selectedQuestions.isEmpty {
            dataManager.message = "暂时没有关联题目，请先用词卡巩固。"
        } else {
            practice = true
        }
    }
}
