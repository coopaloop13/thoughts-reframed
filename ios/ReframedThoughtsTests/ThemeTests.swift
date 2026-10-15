import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ReframedThoughts

struct ThemeTests {
    @Test(arguments: Theme.colorNames)
    func semanticColorExistsInCatalog(name: String) {
        #expect(UIColor(named: name, in: Bundle(for: AppState.self), compatibleWith: nil) != nil, "missing colorset \(name)")
    }

    @Test func displayFontIsSerifTextStyle() {
        #expect(Font.display(.title) == .system(.title, design: .serif, weight: .semibold))
        #expect(Font.display(.body, weight: .regular) == .system(.body, design: .serif, weight: .regular))
    }

    /// Guards ios/CLAUDE.md › UI standards: no raw system colours, no fixed-size display fonts (Dynamic Type).
    @Test func viewsFollowUIStandards() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ReframedThoughts")
        let banned = [#"foregroundStyle\(\.red\)"#, #"\.display\(\d"#]
        var violations: [String] = []
        for case let url as URL in try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)) where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for pattern in banned where text.range(of: pattern, options: .regularExpression) != nil {
                violations.append("\(url.lastPathComponent): \(pattern)")
            }
        }
        #expect(violations.isEmpty, "\(violations)")
    }
}
