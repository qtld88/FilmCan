import SwiftUI

/// ‹ Day02 › in the film header. Thin: all the arithmetic is `ShootDayStepper`.
struct ShootDayStepperView: View {
    let day: String
    let onChange: (String) -> Void
    /// False while a copy runs (`.disabled` on the parent): the whole stepper greys out.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", delta: -1, enabled: ShootDayStepper.canStepBack(day), help: "Previous shoot day")
            Text(day.trimmingCharacters(in: .whitespaces).isEmpty ? "Day —" : day)
                .font(FCType.bodyStrong)
                .foregroundColor(isEnabled ? FilmCanTheme.textPrimary : FilmCanTheme.textTertiary)
                .lineLimit(1)
                .frame(minWidth: 48)
                .help("Shoot day used in the folder names. Type any value in Options › Source.")
            arrow("chevron.right", delta: 1, enabled: ShootDayStepper.canStepForward(day), help: "Next shoot day")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(FilmCanTheme.card)
        .cornerRadius(8)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shoot day")
    }

    private func arrow(_ symbol: String, delta: Int, enabled: Bool, help: String) -> some View {
        Button {
            onChange(ShootDayStepper.step(day, by: delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(enabled && isEnabled ? FilmCanTheme.textSecondary : FilmCanTheme.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
