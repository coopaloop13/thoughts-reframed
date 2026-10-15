import SwiftUI

/// Shown after sign-in, before voice setup or recording: why reframing is worth doing.
struct IntroView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("Negative thoughts are part of life").font(.title).bold()
                Text("Everyone has them. They show up uninvited, especially when life is hard, and having them doesn't mean anything is wrong with you.")
                Text("What helps is noticing a negative thought and actively reframing it into something kinder and truer. Practised over time, that habit makes room for hope and joy even while we're going through trials.")
                Text("Here, you'll say a thought out loud and hear it back reframed, in a clone of your own voice.").foregroundStyle(Color.muted)
                Button("Next") { app.continueFromIntro() }.buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(Theme.spacing)
        }
        .background(Color.sand.ignoresSafeArea())
    }
}
