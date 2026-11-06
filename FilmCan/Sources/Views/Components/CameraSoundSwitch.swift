import SwiftUI

/// Two-position Camera/Sound switch shared by the main window and Quick Copy: the active
/// side is filled, and a click on either side flips it. Picks which destination folder
/// template the source uses.
struct CameraSoundSwitch: View {
    let kind: SourceMediaKind
    let onChange: (SourceMediaKind) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(FilmCanTheme.textPrimary)
                .frame(width: 22, height: 15)
                .offset(x: kind == .camera ? 0 : 22)
            HStack(spacing: 0) {
                segment(.camera, icon: "video.fill")
                segment(.sound, icon: "speaker.wave.2.fill")
            }
        }
        .padding(2)
        .background(Capsule().fill(FilmCanTheme.card))
        .overlay(Capsule().stroke(FilmCanTheme.cardStrokeStrong, lineWidth: 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: kind)
        .help(kind == .camera ? "Camera source — goes to the Camera folder. Click to switch to Sound."
                              : "Sound source — goes to the Sound folder. Click to switch to Camera.")
    }

    private func segment(_ segment: SourceMediaKind, icon: String) -> some View {
        let isOn = segment == kind
        return Button { onChange(kind == .camera ? .sound : .camera) } label: {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isOn ? FilmCanTheme.background : FilmCanTheme.textTertiary)
                .frame(width: 22, height: 15)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment == .camera ? "Camera" : "Sound")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
