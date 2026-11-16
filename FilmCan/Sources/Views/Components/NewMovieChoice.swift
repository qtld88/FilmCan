import SwiftUI
import AppKit

/// "What do you want to start from?": blank, Netflix Ingest, like another movie, or a
/// settings file. Picking one creates the movie and selects it; closing creates
/// nothing. Thin: the rules live in `FilmStarter`, `MovieSettingsFile` and `AppState`.
struct NewMovieChoice: View {
    @ObservedObject var appState: AppState
    /// Closes the popover or sheet.
    var onDone: () -> Void

    var body: some View {
        let films = appState.filmsToStartFrom
        VStack(alignment: .leading, spacing: 4) {
            Text("New movie")
                .font(FCType.cardTitle)
                .padding(.bottom, 4)
            choice("Blank movie", icon: "film", help: "The usual first-run settings.") {
                appState.createNewConfig()
            }
            choice("Netflix Ingest", icon: "n.square", help: "A blank movie with the Netflix Ingest folder settings.") {
                appState.createNetflixIngestConfig()
            }
            if !films.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Same settings as")
                    .font(FCType.meta).foregroundColor(FilmCanTheme.textSecondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(films) { film in
                            choice("Like \(film.name)", icon: "doc.on.doc",
                                   help: "Copies this movie's settings only: no drives, cards, day or episode.") {
                                appState.createNewConfig(like: film)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            Divider().padding(.vertical, 2)
            Button {
                onDone()
                Self.chooseSettingsFile(appState: appState)
            } label: {
                Label("From a settings file\u{2026}", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func choice(_ title: String, icon: String, help: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            action()
            onDone()
        } label: {
            Label(title, systemImage: icon)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .help(help)
    }

    /// Asks for a `.filmcan-movie` file and creates a new movie from it.
    @MainActor
    static func chooseSettingsFile(appState: AppState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MovieSettingsFile.importContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a FilmCan movie settings file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try appState.createNewConfig(fromSettingsFile: data,
                                         fileName: url.deletingPathExtension().lastPathComponent)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't create the movie"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
