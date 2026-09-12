import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

            WordLibraryView()
                .tabItem {
                    Label("词库", systemImage: "book.fill")
                }
                .tag(1)

            PracticeView()
                .tabItem {
                    Label("刷题", systemImage: "pencil.and.list.clipboard")
                }
                .tag(2)

            ErrorWordsView()
                .tabItem {
                    Label("错词", systemImage: "exclamationmark.triangle.fill")
                }
                .tag(3)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Statistics Card
                    VStack(spacing: 15) {
                        Text("学习统计")
                            .font(.headline)

                        HStack(spacing: 20) {
                            StatItem(title: "总词数", value: "\(dataManager.words.count)", color: .blue)
                            StatItem(title: "错词", value: "\(dataManager.errorWords.count)", color: .red)
                            StatItem(title: "收藏", value: "\(dataManager.favoriteWords.count)", color: .orange)
                        }

                        HStack(spacing: 20) {
                            StatItem(title: "已掌握", value: "\(masteredCount)", color: .green)
                            StatItem(title: "学习中", value: "\(learningCount)", color: .purple)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Quick Actions
                    VStack(alignment: .leading, spacing: 15) {
                        Text("快速入口")
                            .font(.headline)
                            .padding(.horizontal)

                        NavigationLink(destination: PracticeView()) {
                            QuickActionCard(icon: "pencil.and.list.clipboard", title: "开始刷题", description: "随机练习题目", color: .blue)
                        }

                        NavigationLink(destination: ErrorWordsView()) {
                            QuickActionCard(icon: "exclamationmark.triangle.fill", title: "错词强化", description: "针对薄弱词训练", color: .red)
                        }

                        NavigationLink(destination: WordLibraryView()) {
                            QuickActionCard(icon: "book.fill", title: "浏览词库", description: "查看所有800词", color: .green)
                        }
                    }

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("花生十三800词")
        }
    }

    private var masteredCount: Int {
        dataManager.studyRecords.values.filter { $0.masteryLevel == .mastered }.count
    }

    private var learningCount: Int {
        dataManager.studyRecords.values.filter { $0.masteryLevel == .learning || $0.masteryLevel == .familiar }.count
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
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
    }
}
