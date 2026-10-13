import SwiftUI

struct ProcessingView: View {
    let label: String
    var body: some View { VStack(spacing: 16) { ProgressView().controlSize(.large); Text(label).foregroundStyle(.secondary) } }
}
