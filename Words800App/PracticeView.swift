import SwiftUI

struct PracticeView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var type = "模拟题"
    @State private var category = "全部分类"
    @State private var count = 10
    @State private var selectedQuestions: [Question] = []
    @State private var presenting = false
    @State private var addingQuestion = false
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        StatItem(title: "已答题", value: "\(dataManager.questionRecords.count)", color: AppStyle.accent)
                        StatItem(title: "正确率", value: "\(dataManager.accuracy)%", color: .green)
                    }
                }
                Section("本次练习") {
                    Picker("题型", selection: $type) {
                        Text("全部题型").tag("全部题型")
                        ForEach(QuestionType.allCases, id: \.self) { item in
                            Text("\(item.rawValue)（\(dataManager.activeQuestions.filter { $0.type == item }.count)）").tag(item.rawValue)
                        }
                    }
                    Picker("词语分类", selection: $category) {
                        Text("全部分类").tag("全部分类")
                        ForEach(dataManager.categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("每组题数", selection: $count) {
                        ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) 题").tag($0) }
                    }
                }
                Section {
                    Button { start(errorsOnly: false) } label: { Label(category == "全部分类" ? "开始随机练习" : "开始分类练习", systemImage: "play.fill") }
                    Button { start(errorsOnly: true) } label: { Label("错词专项训练", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(dataManager.errorWords.isEmpty)
                }
                Section("我的题目") {
                    NavigationLink(destination: PersonalQuestionManager()) { Label("我的题目 · 编辑与归档", systemImage: "square.and.pencil") }
                    Button { addingQuestion = true } label: { Label("添加题目", systemImage: "plus") }
                }
                Section("题库说明") {
                    Text("手动录入的题目单独标注。归档题目或只关联已归档词条的题目不加入新练习。")
                    Text("模拟题是补充编写的逻辑填空练习；释义自测根据你的 PDF 生成，用于词义记忆。两类题分开标注。")
                    Text("真题注明具体考试和公开出处；回忆版与参考解析不等同于官方答案。")
                    Text("错词专项按错误次数优先选题。选定分类没有题目时会明确提示，可以切换到“释义自测”。")
                }.font(.footnote).foregroundColor(.secondary)
            }
            .navigationTitle("刷题")
            .fullScreenCover(isPresented: $presenting) { PracticeSessionView(questions: selectedQuestions) }
        }.navigationViewStyle(.stack)
        .sheet(isPresented: $addingQuestion) { PersonalQuestionEditor() }
    }
    private func start(errorsOnly: Bool) {
        selectedQuestions = dataManager.practiceQuestions(type: type, category: category, errorsOnly: errorsOnly, limit: count, includeArchived: errorsOnly)
        guard !selectedQuestions.isEmpty else { dataManager.message = "这个筛选条件下暂时没有题目，请更换题型或分类。"; return }
        presenting = true
    }
}
struct PracticeSessionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let questions: [Question]
    @State private var index = 0
    @State private var selected: Int?
    @State private var submitted = false
    @State private var answers: [UUID: Int] = [:]
    @State private var confirmExit = false
    private var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    private var correctCount: Int { questions.filter { answers[$0.id] == $0.correctAnswer }.count }
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                let wide = AdaptiveLayoutRules.usesTwoColumns(
                    width: geometry.size.width, height: geometry.size.height,
                    regularWidth: horizontalSizeClass == .regular)
            Group {
                if let question = current {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack { Text("\(index + 1) / \(questions.count)"); Spacer(); Text(question.type.rawValue) }
                                .font(.subheadline).foregroundColor(.secondary)
                            ProgressView(value: Double(index), total: Double(max(1, questions.count)))
                            AdaptivePracticeColumns(wide: wide) {
                                VStack(alignment: .leading, spacing: 16) {
                                    // User-written source notes may reveal the answer; show them only after submission.
                                    if question.personalEntryID == nil || submitted {
                                        Text(question.source).font(.caption).foregroundColor(AppStyle.accent)
                                    }
                                    Text(question.content)
                                        .font(wide ? .title2 : .title3).lineSpacing(8)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 10)
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(question.options.enumerated()), id: \.offset) { option, text in
                                        Button { if !submitted { selected = option } } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                Text(String(["A", "B", "C", "D"][option])).font(.headline)
                                                Text(text).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                                                if submitted && option == question.correctAnswer { Image(systemName: "checkmark.circle.fill") }
                                                else if submitted && selected == option { Image(systemName: "xmark.circle.fill") }
                                            }.padding(18).foregroundColor(optionColor(option, question))
                                                .background(optionColor(option, question).opacity(selected == option || submitted ? 0.09 : 0.04))
                                                .cornerRadius(14)
                                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == option ? optionColor(option, question) : .clear, lineWidth: 1.5))
                                        }.buttonStyle(ResponsivePressButtonStyle()).disabled(submitted)
                                    }
                                    // No explanation, related-word links, or correct-answer styling before submission.
                                    if submitted { ExplanationBody(question: question, selectedAnswer: selected) }
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .padding(wide ? 32 : 20)
                        .frame(maxWidth: 1280)
                        .frame(maxWidth: .infinity)
                    }.id(index)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            if submitted { index += 1; selected = nil; submitted = false }
                            else if let answer = selected, dataManager.submitAnswer(questionId: question.id, selectedAnswer: answer) {
                                answers[question.id] = answer; submitted = true
                            }
                        } label: {
                            Text(submitted ? (index == questions.count - 1 ? "查看本组结果" : "下一题") : "提交答案")
                                .frame(maxWidth: .infinity).padding(10)
                        }.buttonStyle(.borderedProminent).disabled(selected == nil)
                            .frame(maxWidth: wide ? 520 : .infinity)
                            .frame(maxWidth: .infinity, alignment: wide ? .trailing : .center)
                            .padding().background(.regularMaterial)
                    }
                } else {
                    List {
                        Section {
                            VStack(spacing: 12) {
                                Text("本组完成").font(.title.bold())
                                Text("\(correctCount) / \(questions.count)").font(.system(size: 42, weight: .semibold, design: .rounded)).foregroundColor(AppStyle.accent)
                                Text("答对题数 · 错误已记入错词本").foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                        Section("逐题回顾") {
                            ForEach(questions) { question in
                                NavigationLink(destination: QuestionExplanationView(question: question, selectedAnswer: answers[question.id])) {
                                    Label(question.content, systemImage: answers[question.id] == question.correctAnswer ? "checkmark.circle" : "xmark.circle")
                                        .foregroundColor(answers[question.id] == question.correctAnswer ? .green : .red).lineLimit(2)
                                }
                            }
                        }
                        Button("返回刷题") { dismiss() }
                    }
                }
            }
            }
            .navigationTitle("逻辑填空与词义练习").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("结束") { confirmExit = true } } }
            .confirmationDialog("已提交的答题记录会保留。结束本组练习？", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("结束练习") { dismiss() }
                Button("继续答题", role: .cancel) {}
            }
        }.navigationViewStyle(.stack).tint(AppStyle.accent)
    }
    private func optionColor(_ option: Int, _ q: Question) -> Color {
        if submitted && option == q.correctAnswer { return .green }
        if submitted && selected == option { return .red }
        return selected == option ? AppStyle.accent : .primary
    }
}
struct ExplanationBody: View {
    @EnvironmentObject var dataManager: DataManager
    let question: Question
    let selectedAnswer: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("正确答案：\(["A", "B", "C", "D"][question.correctAnswer])").font(.headline).foregroundColor(.green)
            if let answer = selectedAnswer, question.options.indices.contains(answer) {
                Text("你的选择：\(["A", "B", "C", "D"][answer]) · \(answer == question.correctAnswer ? "正确" : "错误")").font(.subheadline)
            }
            Text(question.explanation).lineSpacing(6).textSelection(.enabled)
            if !question.sourceURL.isEmpty, let url = URL(string: question.sourceURL) {
                Link("查看公开出处（需浏览器联网）", destination: url).font(.caption)
            }
            Text("相关词条").font(.headline)
            ForEach(dataManager.relatedWordIDs(for: question), id: \.self) { id in
                if let word = dataManager.word(for: id) {
                    NavigationLink(destination: WordDetailView(word: word)) { Label(word.word, systemImage: "book") }
                }
            }
        }.padding(18).background(Color(.secondarySystemGroupedBackground)).cornerRadius(16)
    }
}
struct QuestionExplanationView: View {
    let question: Question
    let selectedAnswer: Int?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(question.source).font(.caption).foregroundColor(.secondary)
                Text(question.content).font(.title3).lineSpacing(7)
                ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                    Text("\(["A", "B", "C", "D"][i]). \(option)")
                }
                ExplanationBody(question: question, selectedAnswer: selectedAnswer)
            }.padding(20)
        }.navigationTitle("答案解析").navigationBarTitleDisplayMode(.inline)
    }
}
