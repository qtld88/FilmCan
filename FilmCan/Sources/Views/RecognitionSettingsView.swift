import SwiftUI
import AppKit

/// Settings › Recognition: how cards are recognised, the families FilmCan knows, and
/// what it has remembered, with "Forget". Reads `RecognitionGuide` / `RecognitionMemory`.
struct RecognitionSettingsView: View {
    @ObservedObject private var storage = ConfigurationStorage.shared
    @State private var corrections: [RecognitionMemory.Correction] = []
    @State private var movieRolls: [RecognitionMemory.MovieRolls] = []

    var body: some View {
        Form {
            Section("How FilmCan recognises a card") {
                ForEach(RecognitionGuide.signals, id: \.self) { sentence in
                    Text(sentence).fixedSize(horizontal: false, vertical: true)
                }
                Text(RecognitionGuide.whereToSwitch)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Cards it knows") {
                ForEach(RecognitionGuide.families) { family in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: family.isSound ? "waveform" : "video")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text(family.name).frame(width: 130, alignment: .leading)
                        Text(family.recognisedBy)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Your corrections") {
                if corrections.isEmpty {
                    Text("None yet. Right-click a card in Copy From to say what it is.")
                        .foregroundColor(.secondary)
                }
                ForEach(corrections) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(detail(for: item)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Forget") {
                            CardRoleOverrides.set(nil, forVolumeUUID: item.volumeUUID)
                            reload()
                        }
                    }
                }
            }

            Section("Roll names it remembers") {
                if movieRolls.isEmpty {
                    Text("None yet. A card gets a roll name when roll numbering is on for the movie.")
                        .foregroundColor(.secondary)
                } else {
                    Text("A forgotten card gets a new roll name the next time it is used with that movie.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(movieRolls) { movie in
                    DisclosureGroup {
                        ForEach(movie.rolls) { roll in
                            HStack {
                                Text(roll.rollName).font(.system(.body, design: .monospaced))
                                Text(detail(for: roll)).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Forget") {
                                    RollNumberingStore.shared.forgetAssignment(cardKey: roll.cardKey, configId: roll.configId)
                                    reload()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(movie.title)
                            Spacer()
                            Text(summary(for: movie)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        var mounted: [String: String] = [:]
        for volume in FilmDriveDetector.mountedExternalVolumes() {
            if let uuid = FanOutCopier.sourceVolumeUUID(volume.path) {
                mounted[uuid] = FanOutCopier.sourceVolumeName(volume.path)
            }
        }
        corrections = RecognitionMemory.corrections(
            overrides: CardRoleOverrides.all(), details: CardRoleOverrides.details(), mountedNames: mounted)
        movieRolls = RecognitionMemory.rolls(
            states: RollNumberingStore.shared.allStates,
            movies: storage.configurations.map { (id: $0.id, name: $0.name) },
            mountedNames: mounted)
    }

    private func detail(for item: RecognitionMemory.Correction) -> String {
        var parts = [item.roleLabel]
        if let date = item.date { parts.append("corrected " + Self.dateFormatter.string(from: date)) }
        if !item.isConnected, item.driveName != nil { parts.append("not connected") }
        return parts.joined(separator: " · ")
    }

    private func detail(for roll: RecognitionMemory.Roll) -> String {
        var parts: [String] = []
        if let name = roll.driveName { parts.append(name) }
        if !roll.folder.isEmpty { parts.append(roll.folder) }
        return parts.joined(separator: " › ")
    }

    private func summary(for movie: RecognitionMemory.MovieRolls) -> String {
        let count = movie.rolls.count == 1 ? "1 card" : "\(movie.rolls.count) cards"
        guard let lastRun = movie.lastRun else { return count }
        return count + " · last backup " + Self.dateFormatter.string(from: lastRun)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
