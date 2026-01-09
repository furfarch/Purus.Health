import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("MyHealthData")
                    .font(.title)
                    .bold()
                Text("Build: 2026-01, by furfarch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("This app stores medical records locally. Cloud sync and sharing are available in Settings (opt-in).")
                    .multilineTextAlignment(.center)
                    .padding()

                Spacer()
            }
            .padding()
            .navigationTitle("About")
        }
    }
}

#Preview {
    AboutView()
}
