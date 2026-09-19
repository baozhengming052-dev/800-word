import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    @State private var notificationWords: [Word] = []
    @State private var showNotificationReview = false
    @State private var showLaunchBranding = true
    @State private var launchDismissalStarted = false
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView().tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
                WordLibraryView().tabItem { Label("词库", systemImage: "books.vertical.fill") }.tag(1)
                PracticeView().tabItem { Label("刷题", systemImage: "square.and.pencil") }.tag(2)
                ErrorWordsView().tabItem { Label("错词", systemImage: "arrow.triangle.2.circlepath") }.tag(3)
                ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
            }
            if showLaunchBranding {
                CollaborationLaunchView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .tint(AppStyle.accent)
        .onChange(of: selectedTab) { _ in UISelectionFeedbackGenerator().selectionChanged() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                dataManager.refreshDailyMetrics()
                dataManager.scheduleReminderRefresh(after: 1)
            }
        }
        .alert("提示", isPresented: Binding(get: { !dataManager.message.isEmpty }, set: { if !$0 { dataManager.message = "" } })) {
            Button("知道了") { dataManager.message = "" }
        } message: { Text(dataManager.message) }
        .onReceive(NotificationCenter.default.publisher(for: .reviewNotification)) { notification in
            UserDefaults.standard.removeObject(forKey: "pendingNotificationWords")
            let ids = notification.userInfo?["wordIDs"] as? [String] ?? []
            notificationWords = ids.compactMap { UUID(uuidString: $0) }.compactMap { dataManager.activeWord(for: $0) }
            if notificationWords.isEmpty { selectedTab = 3 } else { showNotificationReview = true }
        }
        .onAppear {
            dataManager.scheduleReminderRefresh(after: 1)
            let ids = UserDefaults.standard.stringArray(forKey: "pendingNotificationWords") ?? []
            if !ids.isEmpty {
                notificationWords = ids.compactMap { UUID(uuidString: $0) }.compactMap { dataManager.activeWord(for: $0) }
                showNotificationReview = !notificationWords.isEmpty
                UserDefaults.standard.removeObject(forKey: "pendingNotificationWords")
            }
        }
        .sheet(isPresented: $showNotificationReview) {
            StudySessionView(title: "提醒巩固", words: notificationWords)
        }
        .task {
            guard !launchDismissalStarted else { return }
            launchDismissalStarted = true
            try? await Task.sleep(nanoseconds: reduceMotion ? 700_000_000 : 1_650_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.32)) {
                showLaunchBranding = false
            }
        }
    }
}

private struct CollaborationLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logosVisible = false
    @State private var connectorVisible = false
    @State private var copyVisible = false
    @State private var animationStarted = false

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 700
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.19, blue: 0.41).opacity(0.10),
                        AppStyle.accent.opacity(0.04),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: isWide ? 30 : 24) {
                    Spacer(minLength: isWide ? 28 : 54)

                    VStack(spacing: 8) {
                        Text("联合学习项目")
                            .font(.caption.weight(.semibold))
                            .tracking(3)
                            .foregroundColor(.secondary)
                        Text("湖南工程学院 × 天津商业大学")
                            .font(.system(size: isWide ? 24 : 18, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    .opacity(copyVisible ? 1 : 0)
                    .offset(y: copyVisible ? 0 : 10)

                    CollaborationLogoPair(
                        isWide: isWide,
                        logosVisible: logosVisible,
                        connectorVisible: connectorVisible
                    )

                    VStack(spacing: 10) {
                        Capsule()
                            .fill(AppStyle.accent.opacity(0.35))
                            .frame(width: 42, height: 3)
                        Text("政名政利公考800词")
                            .font(.system(size: isWide ? 31 : 25, weight: .bold, design: .rounded))
                        Text("把见过的词，变成会用的词。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .opacity(copyVisible ? 1 : 0)
                    .offset(y: copyVisible ? 0 : 12)

                    Spacer()

                    HStack(spacing: 7) {
                        Capsule().frame(width: 26, height: 3)
                        Capsule().frame(width: 7, height: 3)
                        Capsule().frame(width: 7, height: 3)
                    }
                    .foregroundColor(AppStyle.accent.opacity(0.65))
                    .opacity(copyVisible ? 1 : 0)
                    .padding(.bottom, max(24, geometry.safeAreaInsets.bottom + 8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("湖南工程学院与天津商业大学联合学习项目，政名政利公考800词")
        .onAppear(perform: startAnimation)
    }

    private func startAnimation() {
        guard !animationStarted else { return }
        animationStarted = true
        if reduceMotion {
            logosVisible = true
            connectorVisible = true
            copyVisible = true
            return
        }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
            logosVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.easeOut(duration: 0.36)) { connectorVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            withAnimation(.easeOut(duration: 0.42)) { copyVisible = true }
        }
    }
}

private struct CollaborationLogoPair: View {
    let isWide: Bool
    let logosVisible: Bool
    let connectorVisible: Bool

    var body: some View {
        HStack(spacing: isWide ? 24 : 12) {
            Image("HNIEBrand")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(maxWidth: isWide ? 230 : 132, maxHeight: isWide ? 72 : 52)
                .accessibilityHidden(true)
                .offset(x: logosVisible ? 0 : (isWide ? -52 : -34))
                .opacity(logosVisible ? 1 : 0)

            VStack(spacing: 6) {
                Text("×")
                    .font(.system(size: isWide ? 28 : 23, weight: .light, design: .rounded))
                Capsule()
                    .fill(AppStyle.accent)
                    .frame(width: isWide ? 28 : 20, height: 3)
            }
            .foregroundColor(AppStyle.accent)
            .scaleEffect(connectorVisible ? 1 : 0.65)
            .opacity(connectorVisible ? 1 : 0)

            Image("TJCUBrand")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(maxWidth: isWide ? 278 : 164, maxHeight: isWide ? 82 : 54)
                .accessibilityHidden(true)
                .offset(x: logosVisible ? 0 : (isWide ? 52 : 34))
                .opacity(logosVisible ? 1 : 0)
        }
        .frame(maxWidth: 650)
        .padding(.horizontal, isWide ? 42 : 20)
        .frame(height: isWide ? 112 : 82)
    }
}

private struct CollaborationHomeMark: View {
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image("HNIEBrand")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(maxWidth: 128, maxHeight: 36)
                    .accessibilityHidden(true)
                Text("×")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundColor(AppStyle.accent)
                Image("TJCUBrand")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(maxWidth: 154, maxHeight: 42)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("联合学习项目")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppStyle.accent.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("湖南工程学院与天津商业大学联合学习项目")
    }
}

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("dailyGoal") private var dailyGoal = 20
    @State private var showLearn = false
    @State private var showReview = false
    @State private var showReminderSetup = false
    var body: some View {
        let todayLearned = dataManager.todayLearnedCount
        let dueWords = dataManager.dueWords
        let errorWords = dataManager.errorWords
        let newWords = dataManager.newWords
        let dueIDs = Set(dueWords.map(\.id))
        let reviewWords = dueWords + errorWords.filter { !dueIDs.contains($0.id) }
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CollaborationHomeMark()
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Date(), style: .date).font(.subheadline).foregroundColor(.secondary)
                        Text("把见过的词，\n变成会用的词。")
                            .font(.system(size: 30, weight: .bold, design: .rounded)).lineSpacing(6)
                        Text("政名政利公考 · 每天一组，反复巩固").font(.subheadline).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("今日学习").font(.headline)
                            Spacer()
                            Text("\(todayLearned)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("/ \(dailyGoal) 词").foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(min(dailyGoal, todayLearned)), total: Double(max(1, dailyGoal)))
                        Button { showLearn = true } label: {
                            Label("开始 / 继续学词", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent)
                        Text("先回忆，再看释义。认识程度由你自己判断。")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(20).background(AppStyle.accent.opacity(0.08)).cornerRadius(20)
                    HStack(spacing: 12) {
                        StatItem(title: "到期复习", value: "\(dueWords.count)", color: .orange)
                        StatItem(title: "高频错词", value: "\(errorWords.count)", color: .red)
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
                    }.buttonStyle(ResponsivePressButtonStyle()).background(Color(.secondarySystemGroupedBackground)).cornerRadius(16)
                    if let word = (errorWords.first ?? newWords.first) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今天重点记住").font(.caption).foregroundColor(.secondary)
                            NavigationLink(destination: WordDetailView(word: word)) {
                                HStack {
                                    Text(word.word).font(.system(size: 28, weight: .bold))
                                    Spacer(); Image(systemName: "chevron.right")
                                }
                            }.buttonStyle(ResponsivePressButtonStyle())
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
                StudySessionView(title: "每日学词", words: Array(newWords.prefix(max(1, dailyGoal - todayLearned))))
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
