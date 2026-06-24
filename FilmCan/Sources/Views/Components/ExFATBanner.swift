import SwiftUI

struct ExFATBanner: View {
    let activeDests: [DestProgress]

    private var shouldShow: Bool {
        activeDests.contains { dp in
            guard dp.requiresFullFsync else { return false }
            switch dp.status {
            case .pending, .active: return true
            case .preparing, .complete, .failed: return false
            }
        }
    }

    private var affectedNames: String {
        activeDests
            .filter { $0.requiresFullFsync }
            .filter { dp in
                switch dp.status {
                case .pending, .active: return true
                default: return false
                }
            }
            .map { $0.displayName }
            .joined(separator: ", ")
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DO NOT UNPLUG — drive cache flush active")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(affectedNames)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.18))
            .cornerRadius(6)
        }
    }
}
