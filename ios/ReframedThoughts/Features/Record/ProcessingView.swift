import SwiftUI

struct ProcessingView: View {
    let label: String
    var body: some View {
        VStack(spacing: Theme.spacing) {
            ProgressView().controlSize(.large).tint(.forest)
            Text(label).font(.display(.title2, weight: .regular)).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sand.ignoresSafeArea())
    }
}
