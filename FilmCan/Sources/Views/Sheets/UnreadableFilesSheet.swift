import SwiftUI

struct UnreadableFilesSheet: View {
    let paths: [String]
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(paths.count) item(s) could not be read and will be skipped:")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(paths, id: \.self) { path in
                        Text((path as NSString).lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Continue Anyway", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
