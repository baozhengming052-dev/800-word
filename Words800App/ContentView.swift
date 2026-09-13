import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    @State private var notificationWords: [Word] = []
    @State private var showNotificationReview = false
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView().tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            WordLibraryView().tabItem { Label("词库", systemImage: "books.vertical.fill") }.tag(1)
            PracticeView().tabItem { Label("刷题", systemImage: "square.and.pencil") }.tag(2)
            ErrorWordsView().tabItem { Label("错词", systemImage: "arrow.triangle.2.circlepath") }.tag(3)
            ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(AppStyle.accent)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                dataManager.objectWillChange.send()
                dataManager.refreshReminder()
            }
        }
        .alert("提示", isPresented: Binding(get: { !dataManager.message.isEmpty }, set: { if !$0 { dataManager.message = "" } })) {
            Button("知道了") { dataManager.message = "" }
        } message: { Text(dataManager.message) }
        .onReceive(NotificationCenter.default.publisher(for: .reviewNotification)) { notification in
            UserDefaults.standard.removeObject(forKey: "pendingNotificationWords")
            let ids = notification.userInfo?["wordIDs"] as? [String] ?? []
            notificationWords = ids.compactMap { id in dataManager.activeWords.first { $0.id.uuidString == id } }
            if notificationWords.isEmpty { selectedTab = 3 } else { showNotificationReview = true }
        }
        .onAppear {
            dataManager.refreshReminder()
            let ids = UserDefaults.standard.stringArray(forKey: "pendingNotificationWords") ?? []
            if !ids.isEmpty {
                notificationWords = ids.compactMap { id in dataManager.activeWords.first { $0.id.uuidString == id } }
                showNotificationReview = !notificationWords.isEmpty
                UserDefaults.standard.removeObject(forKey: "pendingNotificationWords")
            }
        }
        .sheet(isPresented: $showNotificationReview) {
            StudySessionView(title: "提醒巩固", words: notificationWords)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("dailyGoal") private var dailyGoal = 20
    @State private var showLearn = false
    @State private var showReview = false
    @State private var showReminderSetup = false
    private var reviewWords: [Word] {
        let due = dataManager.dueWords
        return due + dataManager.errorWords.filter { w in !due.contains(where: { $0.id == w.id }) }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Date(), style: .date).font(.subheadline).foregroundColor(.secondary)
                        Text("把见过的词，\n变成会用的词。")
                            .font(.system(size: 30, weight: .bold, design: .rounded)).lineSpacing(6)
                        Text("政名政利公考 · 每天一组，反复巩固").font(.subheadline).foregroundColor(.secondary)
                    }.padding(.top, 8)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("今日学习").font(.headline)
                            Spacer()
                            Text("\(dataManager.todayLearnedCount)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("/ \(dailyGoal) 词").foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(min(dailyGoal, dataManager.todayLearnedCount)), total: Double(max(1, dailyGoal)))
                        Button { showLearn = true } label: {
                            Label("开始 / 继续学词", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent)
                        Text("先回忆，再看释义。认识程度由你自己判断。")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(20).background(AppStyle.accent.opacity(0.08)).cornerRadius(20)
                    HStack(spacing: 12) {
                        StatItem(title: "到期复习", value: "\(dataManager.dueWords.count)", color: .orange)
                        StatItem(title: "高频错词", value: "\(dataManager.errorWords.count)", color: .red)
                        StatItem(title: "今日答题", value: "\(dataManager.todayCount)", color: AppStyle.accent)
                    }
                    Button { showReview = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("巩固薄弱词").font(.headline)
                                Text("按错误次数，优先复习容易忘记的词").font(.caption)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill").font(.title)
                        }.padding(18)
                    }.buttonStyle(.plain).background(Color(.secondarySystemGroupedBackground)).cornerRadius(16)
                    if let word = (dataManager.errorWords.first ?? dataManager.newWords.first) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今天重点记住").font(.caption).foregroundColor(.secondary)
                            NavigationLink(destination: WordDetailView(word: word)) {
                                HStack {
                                    Text(word.word).font(.system(size: 28, weight: .bold))
                                    Spacer(); Image(systemName: "chevron.right")
                                }
                            }.buttonStyle(.plain)
                            Text(word.meanings.first ?? "").font(.body).lineSpacing(5)
                            Text(word.isPersonal ? "\(word.category) · 手动添加" : "\(word.category) · 原资料第 \(word.sourcePages) 页").font(.caption).foregroundColor(.secondary)
                        }.padding(20).background(Color(.secondarySystemGroupedBackground)).cornerRadius(16)
                    }
                    Button { showReminderSetup = true } label: {
                        Label("设置每日巩固提醒（默认 20:00）", systemImage: "bell.badge")
                    }.font(.subheadline)
                    Text("已导入 \(dataManager.words.count) 个独立词条；保留原资料的增补与删除标记。")
                        .font(.footnote).foregroundColor(.secondary)
                }.padding(20).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("政名政利公考").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLearn) {
                StudySessionView(title: "每日学词", words: Array(dataManager.newWords.prefix(max(1, dailyGoal - dataManager.todayLearnedCount))))
            }
            .sheet(isPresented: $showReview) {
                StudySessionView(title: "巩固薄弱词", words: Array(reviewWords.prefix(dailyGoal)))
            }
            .sheet(isPresented: $showReminderSetup) { NavigationView { ReminderSettingsView() } }
        }.navigationViewStyle(.stack)
    }
}
struct StatItem: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 7) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(color)
            Text(title).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).background(Color(.secondarySystemGroupedBackground)).cornerRadius(14)
    }
}
extension Notification.Name { static let reviewNotification = Notification.Name("Words800.review") }
