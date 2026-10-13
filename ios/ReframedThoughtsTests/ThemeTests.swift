import Testing
import UIKit
@testable import ReframedThoughts

struct ThemeTests {
    @Test(arguments: Theme.colorNames)
    func semanticColorExistsInCatalog(name: String) {
        #expect(UIColor(named: name, in: Bundle(for: AppState.self), compatibleWith: nil) != nil, "missing colorset \(name)")
    }
}
