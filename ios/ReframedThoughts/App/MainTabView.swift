import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            RecordView().tabItem { Label("Reframe", systemImage: "mic") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
