import SwiftUI

struct EngineHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(UIStrings.EngineHelp.title)
                        .font(.title.bold())
                    Text(UIStrings.EngineHelp.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(UIStrings.EngineHelp.rsyncTitle)
                            .font(.headline)
                        Text(UIStrings.EngineHelp.rsyncSubtitle)

                        Text(UIStrings.EngineHelp.rsyncProsTitle)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        BulletList(UIStrings.EngineHelp.rsyncPros)

                        Text(UIStrings.EngineHelp.rsyncConsTitle)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        BulletList(UIStrings.EngineHelp.rsyncCons)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(UIStrings.EngineHelp.filmCanTitle)
                            .font(.headline)
                        Text(UIStrings.EngineHelp.filmCanSubtitle)

                        Text(UIStrings.EngineHelp.filmCanProsTitle)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        BulletList(UIStrings.EngineHelp.filmCanPros)

                        Text(UIStrings.EngineHelp.filmCanConsTitle)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        BulletList(UIStrings.EngineHelp.filmCanCons)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minWidth: 520, minHeight: 420)
    }
}
