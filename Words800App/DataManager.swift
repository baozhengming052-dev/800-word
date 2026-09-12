import Foundation
import Combine

class DataManager: ObservableObject {
    static let shared = DataManager()

    @Published var words: [Word] = []
    @Published var questions: [Question] = []
    @Published var studyRecords: [UUID: StudyRecord] = [:]
    @Published var questionRecords: [QuestionRecord] = []

    private let wordsKey = "saved_words"
    private let questionsKey = "saved_questions"
    private let studyRecordsKey = "saved_study_records"
    private let questionRecordsKey = "saved_question_records"

    private init() {
        loadData()
        loadSampleData()
    }

    // MARK: - Data Loading
    private func loadData() {
        // Load from UserDefaults
        if let wordsData = UserDefaults.standard.data(forKey: wordsKey),
           let savedWords = try? JSONDecoder().decode([Word].self, from: wordsData) {
            self.words = savedWords
        }

        if let questionsData = UserDefaults.standard.data(forKey: questionsKey),
           let savedQuestions = try? JSONDecoder().decode([Question].self, from: questionsData) {
            self.questions = savedQuestions
        }

        if let recordsData = UserDefaults.standard.data(forKey: studyRecordsKey),
           let savedRecords = try? JSONDecoder().decode([UUID: StudyRecord].self, from: recordsData) {
            self.studyRecords = savedRecords
        }

        if let qRecordsData = UserDefaults.standard.data(forKey: questionRecordsKey),
           let savedQRecords = try? JSONDecoder().decode([QuestionRecord].self, from: qRecordsData) {
            self.questionRecords = savedQRecords
        }
    }

    // MARK: - Data Saving
    func saveData() {
        if let wordsData = try? JSONEncoder().encode(words) {
            UserDefaults.standard.set(wordsData, forKey: wordsKey)
        }

        if let questionsData = try? JSONEncoder().encode(questions) {
            UserDefaults.standard.set(questionsData, forKey: questionsKey)
        }

        if let recordsData = try? JSONEncoder().encode(studyRecords) {
            UserDefaults.standard.set(recordsData, forKey: studyRecordsKey)
        }

        if let qRecordsData = try? JSONEncoder().encode(questionRecords) {
            UserDefaults.standard.set(qRecordsData, forKey: questionRecordsKey)
        }
    }

    // MARK: - Search
    func searchWords(keyword: String) -> [Word] {
        if keyword.isEmpty {
            return words
        }

        let lowercased = keyword.lowercased()
        return words.filter { word in
            word.word.lowercased().contains(lowercased) ||
            word.pinyin.lowercased().contains(lowercased) ||
            word.meanings.joined().lowercased().contains(lowercased) ||
            word.keyPoints.lowercased().contains(lowercased)
        }
    }

    // MARK: - Study Record Management
    func getStudyRecord(for wordId: UUID) -> StudyRecord {
        if let record = studyRecords[wordId] {
            return record
        }

        let newRecord = StudyRecord(wordId: wordId)
        studyRecords[wordId] = newRecord
        saveData()
        return newRecord
    }

    func updateStudyRecord(_ record: StudyRecord) {
        studyRecords[record.wordId] = record
        saveData()
    }

    func addError(for wordId: UUID, context: String) {
        var record = getStudyRecord(for: wordId)
        record.errorCount += 1
        record.errorHistory.append(ErrorRecord(context: context))
        record.lastStudyDate = Date()
        updateStudyRecord(record)
    }

    func toggleFavorite(for wordId: UUID) {
        var record = getStudyRecord(for: wordId)
        record.isFavorite.toggle()
        updateStudyRecord(record)
    }

    func updateMasteryLevel(for wordId: UUID, level: MasteryLevel) {
        var record = getStudyRecord(for: wordId)
        record.masteryLevel = level
        record.lastStudyDate = Date()
        updateStudyRecord(record)
    }

    func updateNotes(for wordId: UUID, notes: String) {
        var record = getStudyRecord(for: wordId)
        record.personalNotes = notes
        updateStudyRecord(record)
    }

    // MARK: - Error Words
    var errorWords: [Word] {
        let errorWordIds = studyRecords.filter { $0.value.errorCount > 0 }
            .sorted { $0.value.errorCount > $1.value.errorCount }
            .map { $0.key }

        return words.filter { errorWordIds.contains($0.id) }
    }

    var favoriteWords: [Word] {
        let favoriteIds = studyRecords.filter { $0.value.isFavorite }.map { $0.key }
        return words.filter { favoriteIds.contains($0.id) }
    }

    // MARK: - Question Management
    func submitAnswer(questionId: UUID, selectedAnswer: Int) {
        guard let question = questions.first(where: { $0.id == questionId }) else { return }

        let isCorrect = selectedAnswer == question.correctAnswer
        let record = QuestionRecord(questionId: questionId, isCorrect: isCorrect, selectedAnswer: selectedAnswer)
        questionRecords.append(record)

        // Update word error records if wrong
        if !isCorrect {
            for wordStr in question.relatedWords {
                if let word = words.first(where: { $0.word == wordStr }) {
                    addError(for: word.id, context: "题目：\(question.content)")
                }
            }
        }

        saveData()
    }

    func getWrongQuestions() -> [Question] {
        let wrongQuestionIds = Set(questionRecords.filter { !$0.isCorrect }.map { $0.questionId })
        return questions.filter { wrongQuestionIds.contains($0.id) }
    }

    // MARK: - Sample Data
    private func loadSampleData() {
        if !words.isEmpty { return }

        // Sample words data
        words = [
            Word(
                word: "鞭辟入里",
                pinyin: "biān pì rù lǐ",
                category: "形容词",
                meanings: ["形容分析深刻透彻，切中要害"],
                keyPoints: "常用于评论、分析等语境，强调见解深刻。注意'辟'读pì，不要误读。",
                confusableWords: [
                    ConfusableWord(word: "入木三分", difference: "入木三分偏重书法或见解深刻，鞭辟入里更强调分析透彻")
                ],
                examples: [
                    Example(sentence: "他的评论鞭辟入里，让人深受启发。", translation: "His comments were incisive and inspiring.")
                ]
            ),
            Word(
                word: "筚路蓝缕",
                pinyin: "bì lù lán lǚ",
                category: "成语",
                meanings: ["驾着柴车，穿着破旧的衣服去开辟山林。形容创业的艰苦。"],
                keyPoints: "用于形容创业艰难，不能用于形容生活贫困。筚：柴车；蓝缕：破旧衣服。",
                confusableWords: [
                    ConfusableWord(word: "栉风沐雨", difference: "栉风沐雨强调奔波劳累，筚路蓝缕强调创业艰辛")
                ],
                examples: [
                    Example(sentence: "他们筚路蓝缕，终于建立了这家企业。", translation: "They went through hardships to establish this company.")
                ]
            ),
            Word(
                word: "标新立异",
                pinyin: "biāo xīn lì yì",
                category: "成语",
                meanings: ["提出新的见解，表示与众不同"],
                keyPoints: "中性词，可褒可贬。褒义指有创新精神，贬义指故意与人不同。",
                confusableWords: [
                    ConfusableWord(word: "独树一帜", difference: "独树一帜多为褒义，标新立异可褒可贬")
                ],
                examples: [
                    Example(sentence: "他总是喜欢标新立异，提出不同看法。", translation: "He always likes to be different and put forward different views.")
                ]
            ),
            Word(
                word: "别具匠心",
                pinyin: "bié jù jiàng xīn",
                category: "成语",
                meanings: ["另有一种巧妙的心思，指在技巧和艺术方面具有与众不同的巧妙构思"],
                keyPoints: "褒义词，用于艺术、设计、创作等方面。",
                confusableWords: [
                    ConfusableWord(word: "独具匠心", difference: "意思相近，可以通用")
                ],
                examples: [
                    Example(sentence: "这座建筑的设计别具匠心。", translation: "The design of this building is ingenious.")
                ]
            ),
            Word(
                word: "不刊之论",
                pinyin: "bù kān zhī lùn",
                category: "成语",
                meanings: ["不能改动或不可磨灭的言论，形容言论精当，无懈可击"],
                keyPoints: "刊：削除，修改。不是'不能刊登'的意思。褒义词。",
                confusableWords: [
                    ConfusableWord(word: "不易之论", difference: "意思相近，都指正确的、不可改变的言论")
                ],
                examples: [
                    Example(sentence: "这篇文章的观点可谓不刊之论。", translation: "The viewpoint of this article is irrefutable.")
                ]
            )
        ]

        // Sample questions
        questions = [
            Question(
                content: "这篇评论对当前经济形势的分析________，切中要害，令人深思。",
                options: ["入木三分", "鞭辟入里", "高屋建瓴", "一针见血"],
                correctAnswer: 1,
                explanation: "鞭辟入里强调分析深刻透彻，最符合'分析'这一语境。入木三分偏重书法或见解，一针见血偏重指出问题，高屋建瓴强调高瞻远瞩。",
                relatedWords: ["鞭辟入里", "入木三分"],
                type: .practice,
                source: "模拟题"
            ),
            Question(
                content: "改革开放初期，许多企业家________，白手起家，终于开创了一番事业。",
                options: ["栉风沐雨", "筚路蓝缕", "披荆斩棘", "风餐露宿"],
                correctAnswer: 1,
                explanation: "筚路蓝缕专门用于形容创业的艰苦，最符合语境。栉风沐雨强调奔波劳累，披荆斩棘强调克服困难，风餐露宿强调旅途艰辛。",
                relatedWords: ["筚路蓝缕", "栉风沐雨"],
                type: .realExam,
                source: "国考2022"
            ),
            Question(
                content: "他的设计________，将传统文化与现代审美完美结合。",
                options: ["别出心裁", "别具匠心", "独树一帜", "标新立异"],
                correctAnswer: 1,
                explanation: "别具匠心强调在技巧和艺术方面的巧妙构思，最适合'设计'这一语境。别出心裁侧重想法新颖，独树一帜强调独特风格，标新立异可褒可贬。",
                relatedWords: ["别具匠心", "标新立异"],
                type: .practice,
                source: "模拟题"
            )
        ]

        saveData()
    }

    // MARK: - Categories
    var categories: [String] {
        Array(Set(words.map { $0.category })).sorted()
    }

    func words(in category: String) -> [Word] {
        words.filter { $0.category == category }
    }
}
