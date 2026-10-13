import SwiftUI

struct MainTabView: View {
    init() {
        // Warm tab bar and nav bar surfaces in both appearances.
        let tab = UITabBarAppearance(); tab.configureWithOpaqueBackground(); tab.backgroundColor = UIColor(named: "Surface")
        UITabBar.appearance().standardAppearance = tab; UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance(); nav.configureWithOpaqueBackground(); nav.backgroundColor = UIColor(named: "Sand")
        nav.titleTextAttributes = [.foregroundColor: UIColor(named: "Bark") ?? .label]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "Bark") ?? .label, .font: UIFont.systemFont(ofSize: 34, weight: .semibold).withSerifDesign()]
        UINavigationBar.appearance().standardAppearance = nav; UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
    var body: some View {
        TabView {
            RecordView().tabItem { Label("Reframe", systemImage: "mic") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

private extension UIFont {
    func withSerifDesign() -> UIFont {
        guard let d = fontDescriptor.withDesign(.serif) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
