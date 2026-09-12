import SwiftUI

@main
struct Words800App: App {
    @StateObject private var dataManager = DataManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
        }
    }
}
