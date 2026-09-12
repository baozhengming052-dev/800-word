import SwiftUI

// MARK: - Error Words View
struct ErrorWordsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var sortBy: SortOption = .errorCount

    enum SortOption: String, CaseIterable {
        case errorCount = "错误次数"
        case recent = "最近错误"

        var icon: String {
            switch self {
            case .errorCount: return "arrow.up.arrow.down"
            case .recent: return "clock"
            }
        }
    }

    var sortedErrorWords: [Word] {
        let words = dataManager.errorWords

        switch sortBy {
        case .errorCount:
            return words.sorted { word1, word2 in
                let record1 = dataManager.getStudyRecord(for: word1.id)
                let record2 = dataManager.getStudyRecord(for: word2.id)
                return record1.errorCount > record2.errorCount
            }
        case .recent:
            return words.sorted { word1, word2 in
                let record1 = dataManager.getStudyRecord(for: word1.id)
                let record2 = dataManager.getStudyRecord(for: word2.id)
                return record1.lastStudyDate > record2.lastStudyDate
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if dataManager.errorWords.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("太棒了！")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("暂无错词记录")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Sort Options
                    HStack {
                        Text("排序方式:")
                            .foregroundColor(.secondary)

                        Picker("排序", selection: $sortBy) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Label(option.rawValue, systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))

                    // Error Words List
                    List(sortedErrorWords) { word in
                        NavigationLink(destination: WordDetailView(word: word)) {
                            ErrorWordRow(word: word)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("错词本")
            .navigationBarItems(trailing:
                Group {
                    if !dataManager.errorWords.isEmpty {
                        NavigationLink(destination: ErrorWordsPracticeView()) {
                            Image(systemName: "flame.fill")
                        }
                    }
                }
            )
        }
    }
}

struct ErrorWordRow: View {
    @EnvironmentObject var dataManager: DataManager
    let word: Word

    var studyRecord: StudyRecord {
        dataManager.getStudyRecord(for: word.id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(word.word)
                    .font(.headline)

                Text(word.pinyin)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(word.meanings.first ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("错\(studyRecord.errorCount)次")
                    .font(.headline)
                    .foregroundColor(.red)

                Text(timeAgo(from: studyRecord.lastStudyDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)

        if days == 0 {
            return "今天"
        } else if days == 1 {
            return "昨天"
        } else if days < 7 {
            return "\(days)天前"
        } else {
            return "\(days / 7)周前"
        }
    }
}

// MARK: - Error Words Practice View
struct ErrorWordsPracticeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        QuestionView(mode: .errorWords) {
            dismiss()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("错词专项训练")
    }
}
