import SwiftUI

/// Before the copy: up to three bands saying what will slow this copy down and what to
/// do about it. After the copy: one sentence naming the slow link. Logic lives in
/// `SpeedAdvisor` / `SpeedNote`; this view only probes off the main thread and shows.
struct SpeedAdviceSection: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    @ObservedObject var transferViewModel: TransferViewModel
    @ObservedObject private var notes = SpeedNoteStore.shared
    let bytesToCopy: Int64
    let refreshToken: Int
    @State private var advices: [SpeedAdvice] = []

    private var isCopying: Bool { transferViewModel.isTransferActive(for: viewModel.config.id) }

    private var probeKey: String {
        let parts: [String] = viewModel.includedSourcePaths + ["→"] + viewModel.includedDestinationPaths
            + [viewModel.destinationCopyMode.rawValue, String(bytesToCopy), String(refreshToken), String(isCopying)]
        return parts.joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isCopying {
                ForEach(advices) { advice in
                    SpeedAdviceBand(
                        advice: advice,
                        onAction: { action in
                            viewModel.applySpeedAdvice(action)
                        },
                        onDismiss: {
                            SpeedAdviceDismissals().dismiss(advice)
                            advices.removeAll { $0.dismissKey == advice.dismissKey }
                        }
                    )
                }
                if let note = notes.notes[viewModel.config.id] {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "speedometer")
                            .foregroundColor(FilmCanTheme.textSecondary)
                        Text(note)
                            .font(FCType.meta)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .task(id: probeKey) { await refresh() }
    }

    @MainActor
    private func refresh() async {
        let sources = viewModel.includedSourcePaths
        let destinations = viewModel.includedDestinationPaths
        let mode = viewModel.destinationCopyMode
        let bytes = bytesToCopy
        guard !isCopying, bytes > 0, !destinations.isEmpty else {
            advices = []
            return
        }
        let dismissed = SpeedAdviceDismissals().keys
        let result = await Task.detached(priority: .utility) { () -> [SpeedAdvice] in
            SpeedAdvisor.advices(
                sources: sources.map { SpeedAdviceProbe.drive(path: $0, role: .source) },
                destinations: destinations.map { SpeedAdviceProbe.drive(path: $0, role: .destination) },
                bytesToCopy: bytes,
                mode: mode,
                dismissed: dismissed)
        }.value
        if !Task.isCancelled { advices = result }
    }
}

struct SpeedAdviceBand: View {
    let advice: SpeedAdvice
    let onAction: (SpeedAdvice.Action) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tortoise.fill")
                .foregroundColor(FilmCanTheme.brandOrange)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(advice.title)
                    .font(FCType.bodyStrong)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text(advice.detail)
                    .font(FCType.meta)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let action = advice.action, case .copyFirst(_, let name) = action {
                        Button("Copy to \(name) first") { onAction(action) }
                            .controlSize(.small)
                    }
                    Button("Dismiss", action: onDismiss)
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmCanTheme.brandOrange.opacity(0.14))
        .cornerRadius(6)
    }
}
