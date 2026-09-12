import SwiftUI

// MARK: - Practice View
struct PracticeView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var practiceMode: PracticeMode = .random
    @State private var isStarted = false

    enum PracticeMode: String, CaseIterable {
        case random = "随机练习"
        case byType = "分类练习"
        case errorWords = "错词专项"

        var icon: String {
            switch self {
            case .random: return "shuffle"
            case .byType: return "list.bullet"
            case .errorWords: return "exclamationmark.triangle.fill"
            }
        }

        var description: String {
            switch self {
            case .random: return "随机抽取题目练习"
            case .byType: return "按题目类型分类练习"
            case .errorWords: return "针对错词强化训练"
            }
        }
    }

    var body: some View {
        NavigationView {
            if isStarted {
                QuestionView(mode: practiceMode, onFinish: {
                    isStarted = false
                })
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Statistics
                        VStack(spacing: 15) {
                            Text("刷题统计")
                                .font(.headline)

                            HStack(spacing: 20) {
                                StatItem(title: "总题数", value: "\(dataManager.questions.count)", color: .blue)
                                StatItem(title: "已做", value: "\(doneCount)", color: .green)
                                StatItem(title: "正确率", value: "\(accuracyRate)%", color: .orange)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // Practice Modes
                        VStack(alignment: .leading, spacing: 15) {
                            Text("选择练习模式")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(PracticeMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    practiceMode = mode
                                    isStarted = true
                                }) {
                                    PracticeModeCard(mode: mode, isDisabled: mode == .errorWords && dataManager.errorWords.isEmpty)
                                }
                                .disabled(mode == .errorWords && dataManager.errorWords.isEmpty)
                            }
                        }

                        Spacer()
                    }
                    .padding(.top)
                }
                .navigationTitle("刷题")
            }
        }
    }

    private var doneCount: Int {
        Set(dataManager.questionRecords.map { $0.questionId }).count
    }

    private var accuracyRate: Int {
        guard !dataManager.questionRecords.isEmpty else { return 0 }
        let correct = dataManager.questionRecords.filter { $0.isCorrect }.count
        return Int(Double(correct) / Double(dataManager.questionRecords.count) * 100)
    }
}

struct PracticeModeCard: View {
    let mode: PracticeView.PracticeMode
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: mode.icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(isDisabled ? Color.gray : Color.blue)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 5) {
                Text(mode.rawValue)
                    .font(.headline)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                Text(mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Question View
struct QuestionView: View {
    @EnvironmentObject var dataManager: DataManager
    let mode: PracticeView.PracticeMode
    let onFinish: () -> Void

    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var showingExplanation = false
    @State private var questions: [Question] = []

    var currentQuestion: Question? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            if let question = currentQuestion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Question Number
                        HStack {
                            Text("第 \(currentQuestionIndex + 1) / \(questions.count) 题")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(question.source)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }

                        // Question Content
                        Text(question.content)
                            .font(.body)
                            .lineSpacing(8)

                        // Options
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            OptionButton(
                                index: index,
                                option: option,
                                isSelected: selectedAnswer == index,
                                isCorrect: index == question.correctAnswer,
                                showResult: showingExplanation
                            ) {
                                if !showingExplanation {
                                    selectedAnswer = index
                                }
                            }
                        }

                        // Explanation
                        if showingExplanation {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: selectedAnswer == question.correctAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(selectedAnswer == question.correctAnswer ? .green : .red)
                                    Text(selectedAnswer == question.correctAnswer ? "回答正确！" : "回答错误")
                                        .fontWeight(.semibold)
                                }
                                .font(.headline)

                                Divider()

                                Text("解析")
                                    .font(.headline)
                                Text(question.explanation)
                                    .foregroundColor(.secondary)

                                if !question.relatedWords.isEmpty {
                                    Divider()

                                    Text("相关词汇")
                                        .font(.headline)

                                    ForEach(question.relatedWords, id: \.self) { wordStr in
                                        if let word = dataManager.words.first(where: { $0.word == wordStr }) {
                                            NavigationLink(destination: WordDetailView(word: word)) {
                                                HStack {
                                                    Text(word.word)
                                                        .foregroundColor(.blue)
                                                    Text("(\(word.pinyin))")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                }

                // Bottom Button
                VStack {
                    if showingExplanation {
                        Button(action: nextQuestion) {
                            Text(currentQuestionIndex < questions.count - 1 ? "下一题" : "完成")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding()
                    } else {
                        Button(action: submitAnswer) {
                            Text("提交答案")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedAnswer != nil ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(selectedAnswer == nil)
                        .padding()
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("暂无题目")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onFinish) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                }
            }
        }
        .onAppear {
            loadQuestions()
        }
    }

    private var progress: CGFloat {
        guard !questions.isEmpty else { return 0 }
        return CGFloat(currentQuestionIndex + 1) / CGFloat(questions.count)
    }

    private func loadQuestions() {
        switch mode {
        case .random:
            questions = dataManager.questions.shuffled()
        case .byType:
            questions = dataManager.questions
        case .errorWords:
            let errorWordStrs = dataManager.errorWords.map { $0.word }
            questions = dataManager.questions.filter { question in
                question.relatedWords.contains(where: { errorWordStrs.contains($0) })
            }.shuffled()
        }
    }

    private func submitAnswer() {
        guard let question = currentQuestion, let answer = selectedAnswer else { return }

        dataManager.submitAnswer(questionId: question.id, selectedAnswer: answer)
        showingExplanation = true
    }

    private func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            showingExplanation = false
        } else {
            onFinish()
        }
    }
}

struct OptionButton: View {
    let index: Int
    let option: String
    let isSelected: Bool
    let isCorrect: Bool
    let showResult: Bool
    let action: () -> Void

    private let letters = ["A", "B", "C", "D"]

    var backgroundColor: Color {
        if !showResult {
            return isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6)
        }

        if isCorrect {
            return Color.green.opacity(0.1)
        } else if isSelected {
            return Color.red.opacity(0.1)
        } else {
            return Color(.systemGray6)
        }
    }

    var borderColor: Color {
        if !showResult {
            return isSelected ? .blue : .clear
        }

        if isCorrect {
            return .green
        } else if isSelected {
            return .red
        } else {
            return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(letters[index])
                    .fontWeight(.semibold)
                    .foregroundColor(showResult ? (isCorrect ? .green : (isSelected ? .red : .primary)) : (isSelected ? .blue : .primary))
                    .frame(width: 30, height: 30)
                    .background(Circle().stroke(borderColor, lineWidth: 2))

                Text(option)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if showResult {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .disabled(showResult)
    }
}
