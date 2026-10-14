import SwiftUI

/// Shown whenever a session or turn is flagged. Not dismissable within the session.
struct CrisisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You deserve support right now").font(.display(20, weight: .medium))
            Text("If you're thinking about harming yourself, please reach out to someone who can help. You don't have to carry this alone.")
                .foregroundStyle(Color.muted)
            Link(destination: URL(string: "tel:988")!) {
                Label("Call 988", systemImage: "phone.fill").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
            Text("Or text HOME to 741741 to reach the Crisis Text Line.").font(.footnote).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
