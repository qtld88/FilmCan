import SwiftUI

/// Hints shown above the editor when what is plugged in will slow the copy down, and
/// one sentence after a copy naming the slow link. Never blocks; each hint can be closed.
struct SpeedAdviceBanner: View {
    let configId: UUID
    let sourcePaths: [String]
    let destinationPaths: [String]
    let mode: DestinationCopyMode
    let isTransferring: Bool
    /// Bytes and seconds of the copy that just ended for this movie, if any.
    let lastCopy: (bytes: Int64, seconds: Double)?
    let onCopyFastFirst: ([String]) -> Void

    @State private var advice: [SpeedAdvice] = []
    @State private var afterCopy: String?
    @State private var refreshTick = 0

    private var signature: String {
        ([configId.uuidString, mode.rawValue, "\(refreshTick)", "\(isTransferring)",
          "\(lastCopy?.bytes ?? 0)"] + sourcePaths + ["→"] + destinationPaths).joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isTransferring {
                ForEach(advice) { item in row(item) }
                if let afterCopy { note(afterCopy) }
            }
        }
        .task(id: signature) { await refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refreshTick += 1
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshTick += 1
        }
    }

    /// Reading drive types asks the system about each drive: done off the main thread.
    private func refresh() async {
        guard !isTransferring else { return }
        let sources = sourcePaths, destinations = destinationPaths, mode = mode, lastCopy = lastCopy
        let result = await Task.detached(priority: .utility) { () -> ([SpeedAdvice], String?) in
            let fm = FileManager.default
            let sourceDrives = sources.filter { fm.fileExists(atPath: $0) }.map(SpeedAdvisor.drive(at:))
            let destinationDrives = destinations.filter { fm.fileExists(atPath: $0) }.map(SpeedAdvisor.drive(at:))
            let bytes = sources.reduce(Int64(0)) { sum, path in
                let capacity = DriveUtilities.capacity(for: path)
                guard let total = capacity.total, let available = capacity.available else { return sum }
                // A card is usually copied whole: what it holds is the best quick estimate.
                return sum + max(0, total - available)
            }
            let hints = SpeedAdvisor.advice(sources: sourceDrives, destinations: destinationDrives, mode: mode,
                                            bytesToCopy: bytes, dismissed: SpeedAdvisor.dismissed())
            let sentence = lastCopy.flatMap {
                SpeedAdvisor.slowLink(bytesCopied: $0.bytes, seconds: $0.seconds,
                                      sources: sourceDrives, destinations: destinationDrives)
            }
            return (hints, sentence)
        }.value
        guard !Task.isCancelled else { return }
        advice = result.0
        afterCopy = result.1
    }

    private func row(_ item: SpeedAdvice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tortoise.fill")
                .foregroundColor(FilmCanTheme.brandOrange)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(FCType.bodyStrong)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text(item.detail)
                    .font(FCType.meta)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let title = item.actionTitle, case .copyFastFirst(let order, _) = item.action {
                Button(title) {
                    onCopyFastFirst(order)
                    refreshTick += 1
                }
            }
            Button {
                SpeedAdvisor.dismiss(item.id)
                advice.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close. This hint will not come back for these drives.")
            .accessibilityLabel("Close this hint")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmCanTheme.brandOrange.opacity(0.14))
        .overlay(alignment: .bottom) { Divider().background(FilmCanTheme.cardStroke) }
    }

    private func note(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer").foregroundColor(FilmCanTheme.textSecondary)
            Text(text)
                .font(FCType.meta)
                .foregroundColor(FilmCanTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().background(FilmCanTheme.cardStroke) }
    }
}
