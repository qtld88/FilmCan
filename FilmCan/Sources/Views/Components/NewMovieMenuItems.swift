import SwiftUI

/// "Like <movie>" and "From preset <name>" entries, shared by the "+" menu in the
/// tab bar and the File menu. Thin: the copying rules live in `AppState` and
/// `BackupConfiguration.newFilm(name:like:)`.
struct NewMovieMenuItems: View {
    @ObservedObject var appState: AppState
    @ObservedObject var storage: ConfigurationStorage

    var body: some View {
        let films = appState.filmsToStartFrom
        let presets = appState.presetsToStartFrom
        if !films.isEmpty {
            Section("Same settings as") {
                ForEach(films) { film in
                    Button("Like \(film.name)") { appState.createNewConfig(like: film) }
                }
            }
        }
        if !presets.isEmpty {
            Section("Start from a preset") {
                ForEach(presets) { preset in
                    Button("From preset \(preset.name)") { appState.createNewConfig(fromPreset: preset) }
                }
            }
        }
    }
}
