import AppKit
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var store: MediaCatalogStore
    @State private var query = ""
    @State private var mounted: Set<String> = []
    @State private var rollToForget: CatalogRoll?
    /// "A001 on SSD_1" while a report is being created; one at a time.
    @State private var reportInProgress: String?
    @State private var reportFailure: String?

    /// Set when hosted in the main window's right pane; nil in the standalone window.
    var paneWidth: CGFloat? = nil

    private var isCompact: Bool { (paneWidth ?? .infinity) < 420 }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().background(FilmCanTheme.cardStroke)
            if let reportInProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Creating the report for \(reportInProgress)…")
                        .font(FCType.metaStrong)
                        .foregroundColor(FilmCanTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            if trimmedQuery.isEmpty {
                coverageList
            } else {
                resultsList
            }
        }
        .frame(minWidth: paneWidth == nil ? 560 : 0, minHeight: 360)
        .background(FilmCanTheme.background)
        .onAppear { mounted = store.mountedVolumeUUIDs() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            mounted = store.mountedVolumeUUIDs()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            mounted = store.mountedVolumeUUIDs()
        }
        .alert("Forget this roll?", isPresented: Binding(
            get: { rollToForget != nil },
            set: { if !$0 { rollToForget = nil } })
        ) {
            Button("Forget", role: .destructive) {
                if let roll = rollToForget { store.forget(rollId: roll.id) }
                rollToForget = nil
            }
            Button("Cancel", role: .cancel) { rollToForget = nil }
        } message: {
            Text("The roll is removed from the catalog only. No file is deleted.")
        }
        .alert("The report could not be created", isPresented: Binding(
            get: { reportFailure != nil },
            set: { if !$0 { reportFailure = nil } })
        ) {
            Button("OK", role: .cancel) { reportFailure = nil }
        } message: {
            Text(reportFailure ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(FilmCanTheme.textSecondary)
            TextField("Search clip name (e.g. C0042)", text: $query)
                .textFieldStyle(.plain)
                .font(FilmCanFont.body(13))
                .foregroundColor(FilmCanTheme.textPrimary)
        }
        .padding(12)
    }

    // MARK: Coverage mode

    private var coverageList: some View {
        let atRisk = MediaCatalog.atRisk(store.rolls)
        return Group {
            if store.rolls.isEmpty {
                placeholder("No roll recorded yet. Rolls appear here after their first backup.")
            } else {
                List {
                    if !atRisk.isEmpty {
                        Text("\(atRisk.count) roll\(atRisk.count == 1 ? " is" : "s are") on one drive only. Copy \(atRisk.count == 1 ? "it" : "them") to a second drive before formatting the card.")
                            .font(FCType.bodyStrong)
                            .foregroundColor(FilmCanTheme.brandOrange)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FilmCanTheme.brandOrange.opacity(0.12))
                            .cornerRadius(6)
                    }
                    ForEach(projectGroups, id: \.name) { project in
                        ForEach(project.days, id: \.day) { day in
                            Section(header: Text("\(project.name) › \(day.day)")
                                .font(FCType.bodyStrong)
                                .foregroundColor(FilmCanTheme.textSecondary)) {
                                ForEach(day.rolls) { roll in
                                    rollRow(roll)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct DayGroup { var day: String; var rolls: [CatalogRoll]; var newest: Date }
    private struct ProjectGroup { var name: String; var days: [DayGroup] }

    private var projectGroups: [ProjectGroup] {
        let byProject = Dictionary(grouping: store.rolls, by: \.projectName)
        return byProject.keys.sorted().map { name in
            let byDay = Dictionary(grouping: byProject[name] ?? [], by: \.shootDay)
            let days = byDay.map { day, rolls in
                DayGroup(day: day,
                         rolls: rolls.sorted { $0.rollName < $1.rollName },
                         newest: rolls.map(\.firstBackedUp).max() ?? .distantPast)
            }.sorted { $0.newest > $1.newest }
            return ProjectGroup(name: name, days: days)
        }
    }

    private func rollRow(_ roll: CatalogRoll) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: roll.mediaKind == .sound ? "waveform" : "camera")
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(roll.rollName)
                        .font(FCType.itemTitle)
                        .foregroundColor(FilmCanTheme.textPrimary)
                    Text(roll.files.isEmpty
                         ? "Files not indexed · \(Self.byteFormatter.string(fromByteCount: roll.totalBytes))"
                         : "\(roll.files.count) files · \(Self.byteFormatter.string(fromByteCount: roll.totalBytes))")
                        .font(FCType.metaStrong)
                        .foregroundColor(FilmCanTheme.textTertiary)
                }
                if isCompact {
                    chipsAndBadge(roll.copies, coverage: roll.coverage) { reveal($0, relPath: nil) }
                }
            }
            if !isCompact {
                Spacer(minLength: 8)
                chipsAndBadge(roll.copies, coverage: roll.coverage) { reveal($0, relPath: nil) }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            revealMenu(roll.copies, relPath: nil)
            Divider()
            reportMenu(roll)
            Divider()
            Button("Forget this roll") { rollToForget = roll }
        }
    }

    private func chipsAndBadge(_ copies: [CatalogCopy], coverage: CatalogCoverage?, onReveal: @escaping (CatalogCopy) -> Void) -> some View {
        HStack(spacing: 6) {
            driveChips(copies, onReveal: onReveal)
            if let coverage { coverageBadge(coverage) }
        }
    }

    private func distinctDrives(_ copies: [CatalogCopy]) -> [CatalogCopy] {
        var seen = Set<String>()
        return copies.filter { seen.insert($0.driveKey).inserted }
    }

    @ViewBuilder
    private func revealMenu(_ copies: [CatalogCopy], relPath: String?) -> some View {
        ForEach(distinctDrives(copies), id: \.driveKey) { copy in
            if isMounted(copy) {
                Button("Reveal on \(copy.destVolumeName)") { reveal(copy, relPath: relPath) }
            } else {
                Button("Reveal on \(copy.destVolumeName) (not connected)") {}
                    .disabled(true)
            }
        }
    }

    /// One pair of entries per connected drive that holds the roll.
    @ViewBuilder
    private func reportMenu(_ roll: CatalogRoll) -> some View {
        let connected = distinctDrives(roll.copies).filter { isMounted($0) }
        if connected.isEmpty {
            Button("Create report (connect a drive that holds this roll)") {}
                .disabled(true)
        }
        ForEach(connected, id: \.driveKey) { copy in
            Button("Create report from \(copy.destVolumeName)") {
                createReport(roll, copy, recheck: false)
            }
            .disabled(reportInProgress != nil)
            Button("Create report from \(copy.destVolumeName), re-reading every file (slow)") {
                createReport(roll, copy, recheck: true)
            }
            .disabled(reportInProgress != nil)
        }
    }

    private func createReport(_ roll: CatalogRoll, _ copy: CatalogCopy, recheck: Bool) {
        guard reportInProgress == nil else { return }
        reportInProgress = "\(roll.rollName) on \(copy.destVolumeName)"
        Task.detached(priority: .userInitiated) {
            let path = await BackupReportWriter.recreate(roll: roll, copy: copy, recheck: recheck)
            await MainActor.run {
                reportInProgress = nil
                if let path {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } else {
                    reportFailure = "\(roll.rollName) was not found on \(copy.destVolumeName), or the PDF could not be written to the reports folder."
                }
            }
        }
    }

    /// Selects the file when it exists on that drive, otherwise the roll folder.
    private func reveal(_ copy: CatalogCopy, relPath: String?) {
        let folder = URL(fileURLWithPath: copy.rollFolderPath)
        var target = folder
        if let relPath {
            let file = folder.appendingPathComponent(relPath)
            if FileManager.default.fileExists(atPath: file.path) { target = file }
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func isMounted(_ copy: CatalogCopy) -> Bool {
        if let uuid = copy.destVolumeUUID { return mounted.contains(uuid) }
        return FileManager.default.fileExists(atPath: copy.rollFolderPath)
    }

    /// One chip per distinct drive; a connected chip reveals the item on that drive.
    private func driveChips(_ copies: [CatalogCopy], onReveal: @escaping (CatalogCopy) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(distinctDrives(copies), id: \.driveKey) { copy in
                let connected = isMounted(copy)
                Button { onReveal(copy) } label: {
                HStack(spacing: 4) {
                    Circle()
                        .strokeBorder(FilmCanTheme.textSecondary, lineWidth: 1)
                        .background(Circle().fill(isMounted(copy) ? FilmCanTheme.textPrimary : Color.clear))
                        .frame(width: 7, height: 7)
                    Text(copy.destVolumeName)
                        .font(FCType.metaStrong)
                        .foregroundColor(FilmCanTheme.textPrimary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(copy.verified ? FilmCanTheme.brandGreen.opacity(0.25) : FilmCanTheme.card)
                .cornerRadius(6)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!connected)
                .help(connected ? "Reveal on \(copy.destVolumeName)" : "\(copy.destVolumeName) not connected")
                .accessibilityLabel(connected ? "Reveal on \(copy.destVolumeName)" : "\(copy.destVolumeName), not connected")
            }
        }
    }

    private func coverageBadge(_ coverage: CatalogCoverage) -> some View {
        let (text, color): (String, Color) = {
            switch coverage {
            case .safe(let n): return ("\(n)× ✓", FilmCanTheme.brandGreen)
            case .single: return ("1 drive only", FilmCanTheme.brandOrange)
            case .unverified: return ("Not verified", FilmCanTheme.textTertiary)
            }
        }()
        return Text(text)
            .font(FCType.metaStrong)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    // MARK: Search mode

    private var resultsList: some View {
        let limit = 200
        let hits = MediaCatalog.search(trimmedQuery, in: store.rolls, limit: limit)
        return Group {
            if hits.isEmpty {
                placeholder("No clip matches “\(trimmedQuery)”.")
            } else {
                List {
                    ForEach(hits) { hit in
                        let hitCoverage = store.rolls.first(where: { $0.id == hit.rollId })?.coverage
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((hit.file.relPath as NSString).lastPathComponent)
                                        .font(FCType.itemTitle)
                                        .foregroundColor(FilmCanTheme.textPrimary)
                                    Text("\(hit.projectName) › \(hit.shootDay) › \(hit.rollName)")
                                        .font(FCType.metaStrong)
                                        .foregroundColor(FilmCanTheme.textTertiary)
                                }
                                if isCompact {
                                    chipsAndBadge(hit.copies, coverage: hitCoverage) { reveal($0, relPath: hit.file.relPath) }
                                }
                            }
                            if !isCompact {
                                Spacer(minLength: 8)
                                chipsAndBadge(hit.copies, coverage: hitCoverage) { reveal($0, relPath: hit.file.relPath) }
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if let copy = hit.copies.first(where: { isMounted($0) }) {
                                reveal(copy, relPath: hit.file.relPath)
                            }
                        }
                        .contextMenu { revealMenu(hit.copies, relPath: hit.file.relPath) }
                    }
                    if hits.count >= limit {
                        Text("Showing first \(limit) results")
                            .font(FCType.metaStrong)
                            .foregroundColor(FilmCanTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(FilmCanFont.body(13))
            .foregroundColor(FilmCanTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
