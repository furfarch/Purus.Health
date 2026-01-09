import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MyHealthData")
                        .font(.title)
                        .bold()

                    Text("Data & Privacy")
                        .font(.headline)
                        .padding(.top, 8)

                    Text("This app lets you store health and medical information securely on your device. By default, all data remains stored locally.")

                    Text("You can optionally enable cloud synchronization to access your data across multiple devices or share it with other people. When cloud sync is enabled, your data is transferred to and stored on Apple iCloud servers and protected using Apple’s standard encryption.")

                    Text("Please note that if you choose to export your data and store it externally, the exported files are not encrypted.")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("About")
        }
    }
}

#Preview {
    AboutView()
}
