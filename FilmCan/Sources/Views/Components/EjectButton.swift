import SwiftUI

/// Eject icon for one source/destination row. Hidden for paths on the boot disk,
/// disabled while a copy uses the drive.
struct EjectButton: View {
    let path: String
    /// Sources warn before ejecting a card FilmCan hasn't sealed as backed up.
    var warnIfUnsealed: Bool = false
    var onEjected: () -> Void = {}
    var onError: (String) -> Void

    @ObservedObject private var volumesInUse = VolumesInUse.shared
    @State private var isEjecting = false

    var body: some View {
        if VolumesInUse.volumeRoot(for: path) != nil {
            let busy = volumesInUse.isBusy(path: path)
            Button {
                isEjecting = true
                Task { @MainActor in
                    let outcome = await VolumeEjectFlow.eject(path: path, warnIfUnsealed: warnIfUnsealed)
                    isEjecting = false
                    switch outcome {
                    case .ejected: onEjected()
                    case .cancelled: break
                    case .failed(let message): onError(message)
                    }
                }
            } label: {
                Image(systemName: "eject")
            }
            .buttonStyle(.plain)
            .foregroundColor(FilmCanTheme.textSecondary)
            .disabled(busy || isEjecting)
            .opacity(busy ? 0.35 : 1)
            .help(busy ? "Can't eject while a copy is using this drive" : "Eject drive")
        }
    }
}
