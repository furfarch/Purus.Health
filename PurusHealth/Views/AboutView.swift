import SwiftUI

struct AboutView: View {
    private var yearMonthStamp: String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: now)
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        // shown inside Settings (pushed), so no own NavigationStack
        Group {
            VStack(spacing: 12) {
                Text("Purus Health")
                    .font(.title)
                    .bold()
                Text("Build: \(yearMonthStamp) • build \(buildNumber) • by furfarch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Data & Privacy\nThis app lets you store health and medical information securely on your device. By default, all data remains stored locally.\n\nYou can optionally enable cloud synchronization to access your data across multiple devices or share it with other people. When cloud sync is enabled, your data is transferred to and stored on Apple iCloud servers and protected using Apple’s standard encryption.\n\nPlease note that if you choose to export your data and store it externally, the exported files are not encrypted.")
                    .frame(maxWidth: .infinity, alignment: .leading)
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
