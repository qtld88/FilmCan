import SwiftUI

struct DriveSettingsView: View {
    @Binding var disableSpotlightIndexing: Bool

    var body: some View {
        Form {
            Section("Spotlight") {
                Toggle("Disable Spotlight indexing on backup drives", isOn: $disableSpotlightIndexing)
                Text("Drops a `.metadata_never_index` marker on each source card and destination drive at backup start, so macOS stops indexing them mid-copy. Only external/removable volumes are affected — your internal disk is never touched. The marker is left in place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
