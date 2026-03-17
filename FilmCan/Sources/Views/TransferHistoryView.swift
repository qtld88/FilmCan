import SwiftUI

struct TransferHistoryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var transferViewModel: TransferViewModel
    @AppStorage("historyListView") private var historyListView: Bool = false
    @State private var verificationSheet: VerificationAlert? = nil
    @State private var verifyingHashPaths: Set<String> = []
    @State private var verificationStatusByDestination: [String: VerificationStatus] = [:]
    @State private var resumeError: String? = nil
    @State private var showClearConfirmation: Bool = false
    @State private var searchText: String = ""
    @State private var statusFilter: HistoryStatusFilter = .all
    @State private var deleteCandidate: TransferHistoryEntry? = nil
    @State private var sortOption: HistorySortOption = .mostRecent
    @State private var historyCounts: [UUID: HistoryCounts] = [:]
    private let historyCardOuter = Color(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 56.0 / 255.0)
    private let historyCardMiddle = Color(white: 0.4)
    private let historyCardInner = Color(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 56.0 / 255.0)
    private let historyCardStroke = Color(white: 0.16)
    private let historyCardStrokeStrong = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("History")
                        .font(FilmCanFont.title(16))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    Spacer()
                    Toggle(isOn: $historyListView) {
                        Text("List view")
                            .font(FilmCanFont.body(10))
                            .foregroundColor(FilmCanTheme.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(FilmCanTheme.textSecondary)
                    TextField("Search history", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(FilmCanTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(FilmCanTheme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    Menu {
                        ForEach(HistoryStatusFilter.allCases) { option in
                            Button(action: { statusFilter = option }) {
                                HStack(spacing: 6) {
                                    if statusFilter == option {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Color.clear.frame(width: 12, height: 12)
                                    }
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(statusFilter.label)
                                .font(FilmCanFont.label(9))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(FilmCanTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Menu {
                        ForEach(HistorySortOption.allCases) { option in
                            Button(action: { sortOption = option }) {
                                HStack(spacing: 6) {
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Color.clear.frame(width: 12, height: 12)
                                    }
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(FilmCanTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort history")
                }
                .padding(8)
                .background(FilmCanTheme.card)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
                )
            }
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if historyListView {
                        ForEach(sortedHistoryEntries) { entry in
                            historyListRow(entry)
                        }
                    } else {
                        ForEach(sortedSourceItems) { item in
                            sourceHistoryCard(item)
                        }
                    }

                    if visibleHistoryIsEmpty {
                        Text(emptyHistoryMessage)
                            .font(FilmCanFont.body(11))
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(16)
            }

            Divider()
                .opacity(0.4)

            HStack {
                Spacer()
                Button(action: { showClearConfirmation = true }) {
                    Text(clearHistoryLabel)
                        .font(FilmCanFont.label(11))
                        .foregroundColor(canClearHistory ? FilmCanTheme.textSecondary : FilmCanTheme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(FilmCanTheme.card)
                .cornerRadius(8)
                .disabled(!canClearHistory)
                .help(clearHistoryHelp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 180, idealWidth: 210, maxWidth: 255)
        .background(FilmCanTheme.sidebar)
        .sheet(item: $verificationSheet) { alert in
            VerificationAlertSheet(alert: alert)
        }
        .alert("Cannot Resume", isPresented: Binding(
            get: { resumeError != nil },
            set: { _ in resumeError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resumeError ?? "")
        }
        .confirmationDialog("Clear history?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button(clearHistoryConfirmLabel, role: .destructive) { performClearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearHistoryWarning)
        }
        .confirmationDialog(
            "Delete history entry?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deleteCandidate {
                    deleteHistoryEntry(entry)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text(deleteHistoryMessage)
        }
    }
    
    private func sourceHistoryCard(_ item: SourceItem) -> some View {
        let entry = item.entry
        let sourceName = sourceDisplayName(item)
        let lightInset: CGFloat = 8
        let innerInset: CGFloat = 13
        let stickerHeight: CGFloat = 31
        let bottomPadding = stickerHeight + 20
        let outerStrokeColor = entry.success ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed
        return ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(historyCardOuter)
            RoundedRectangle(cornerRadius: 40)
                .stroke(outerStrokeColor, lineWidth: 1)
            RoundedRectangle(cornerRadius: 35)
                .fill(historyCardMiddle)
                .padding(lightInset)
            RoundedRectangle(cornerRadius: 35)
                .fill(historyCardInner)
                .padding(innerInset)
            RoundedRectangle(cornerRadius: 35)
                .stroke(historyCardStrokeStrong, lineWidth: 1)
                .padding(lightInset)

            VStack(spacing: 8) {
                Text(displayConfigName(for: entry))
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, -4)

                Text(sourceName)
                    .font(FilmCanFont.title(27))
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .help(sourceHoverText(for: entry))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.results) { result in
                        HStack(spacing: 6) {
                            destinationStatusIcon(for: result, entryId: entry.id)
                            Text(truncatedDestinationName(result.destination))
                                .font(FilmCanFont.label(11))
                                .foregroundColor(FilmCanTheme.textSecondary)
                                .help(destinationHoverText(for: result))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)

            Spacer(minLength: 0)
            if let presetLabel = presetLabel(for: entry) {
                Text(presetLabel)
                    .font(FilmCanFont.label(10))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(FilmCanTheme.brandYellow)
            }

            }
            .padding(.top, innerInset + 2)
            .padding(.horizontal, innerInset)
            .padding(.bottom, bottomPadding)
            .frame(maxHeight: .infinity)

            if entry.success {
                historySticker(text: historyDateLabel(entry.endedAt))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 0)
            } else {
                Text("FAILED")
                    .font(FilmCanFont.title(18))
                    .foregroundColor(FilmCanTheme.brandRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .help(entryErrorMessage(entry) ?? "")
            }
        }
        .frame(width: 200, height: 200)
        .contextMenu {
            Button("Use it again") { recallSettings(from: entry) }
            if !entry.results.isEmpty {
                Divider()
            }
            ForEach(entry.results) { result in
                let destName = (result.destination as NSString).lastPathComponent
                let label = "Check data for \(destName)"
                let target = hashTarget(for: entry, result: result)
                Button(label) {
                    guard let target else { return }
                    runVerification(entry: entry, hashPath: target.path, roots: target.roots)
                }
                .disabled(
                    target == nil
                        || verifyingHashPaths.contains(target?.path ?? "")
                        || !(target.map { canVerifyHashPath($0.path) } ?? false)
                )
            }
            Divider()
            Button("Delete history card", role: .destructive) { deleteCandidate = entry }
        }
        .task(id: entry.id) {
            await loadHistoryCounts(entry: entry)
        }
    }

    private struct DestinationItem: Identifiable {
        let id: UUID = UUID()
        let entry: TransferHistoryEntry
        let result: TransferResultRecord
    }

    private struct SourceItem: Identifiable {
        let id: String
        let entry: TransferHistoryEntry
        let source: String
    }

    private struct VerificationSummary {
        let total: Int
        let missing: Int
        let mismatched: Int
        let failedLists: Int
    }

    private struct VerificationDetails {
        let summary: VerificationSummary
        let verifiedDestinations: [String]
        let uncheckedDestinations: [String]
        let logIncluded: Bool
        let runDate: Date
    }

    private struct VerificationAlert: Identifiable {
        let id = UUID()
        let message: String
        let details: VerificationDetails?
    }

    private var filteredHistoryEntries: [TransferHistoryEntry] {
        baseHistoryEntries.filter { entry in
            matchesStatus(success: entry.success) && matchesSearch(entry: entry)
        }
    }

    private var sourceItems: [SourceItem] {
        baseHistoryEntries.flatMap { entry in
            let sources = entry.sources.isEmpty ? [""] : entry.sources
            return sources.map { source in
                SourceItem(id: "\(entry.id.uuidString)|\(source)", entry: entry, source: source)
            }
        }
    }

    private var filteredSourceItems: [SourceItem] {
        sourceItems.filter { item in
            matchesStatus(success: item.entry.success) && matchesSearch(item: item)
        }
    }

    private var destinationItems: [DestinationItem] {
        baseHistoryEntries
            .flatMap { entry in
                entry.results.map { DestinationItem(entry: entry, result: $0) }
            }
            .filter { item in
                matchesStatus(success: item.result.success) && matchesSearch(item: item)
            }
    }

    private var sortedHistoryEntries: [TransferHistoryEntry] {
        sortEntries(filteredHistoryEntries)
    }

    private var sortedSourceItems: [SourceItem] {
        sortSourceItems(filteredSourceItems)
    }

    private var sortedDestinationItems: [DestinationItem] {
        sortDestinationItems(destinationItems)
    }

    private var baseHistoryEntries: [TransferHistoryEntry] {
        guard let selectedId = appState.selectedConfigId else { return [] }
        return appState.storage.transferHistory.filter { $0.configId == selectedId }
    }

    private var visibleHistoryIsEmpty: Bool {
        if appState.storage.transferHistory.isEmpty {
            return true
        }
        if historyListView {
            return sortedHistoryEntries.isEmpty
        }
        return sortedSourceItems.isEmpty
    }

    private var emptyHistoryMessage: String {
        if appState.storage.transferHistory.isEmpty {
            return "No transfers yet"
        }
        return "No matches"
    }

    private var canClearHistory: Bool {
        return appState.selectedConfigId != nil && !baseHistoryEntries.isEmpty
    }

    private var clearHistoryLabel: String {
        "Clear this history"
    }

    private var clearHistoryConfirmLabel: String {
        "Clear this history"
    }

    private var clearHistoryHelp: String {
        return "Remove history entries for the selected backup."
    }

    private var clearHistoryWarning: String {
        return "This will delete all history entries for the selected backup. The last run status will be cleared."
    }

    private func performClearHistory() {
        if let selectedId = appState.selectedConfigId {
            appState.storage.clearHistory(for: selectedId)
            transferViewModel.clearLastRun(for: selectedId)
        }
    }

    private func historyListRow(_ entry: TransferHistoryEntry) -> some View {
        let isSuccess = entry.success
        let color = isSuccess ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(color)
                    .font(.system(size: 12, weight: .semibold))
                Text(sourceLabelText(for: entry.sources))
                    .font(FilmCanFont.body(12))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            if !isSuccess, let error = entryErrorMessage(entry), !error.isEmpty {
                Text(error)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryErrorMessage(_ entry: TransferHistoryEntry) -> String? {
        let message = entry.results.compactMap { $0.errorMessage }.first
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private func destinationCard(_ item: DestinationItem) -> some View {
        let result = item.result
        let lightInset: CGFloat = 8
        let innerInset: CGFloat = 13
        let stickerHeight: CGFloat = 31
        let bottomPadding = stickerHeight + 20
        let outerStrokeColor = result.success ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed
        return ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(historyCardOuter)
            RoundedRectangle(cornerRadius: 26)
                .stroke(outerStrokeColor, lineWidth: 1)
            RoundedRectangle(cornerRadius: 20)
                .fill(historyCardMiddle)
                .padding(lightInset)
            RoundedRectangle(cornerRadius: 15)
                .fill(historyCardInner)
                .padding(innerInset)
            RoundedRectangle(cornerRadius: 20)
                .stroke(historyCardStrokeStrong, lineWidth: 1)
                .padding(lightInset)

            VStack(spacing: 8) {
                Text(displayConfigName(for: item.entry))
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, -4)

                Text(sourceLabelText(for: item.entry.sources))
                    .font(FilmCanFont.title(24))
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .help(sourceHoverText(for: item.entry))

                HStack(spacing: 6) {
                    destinationStatusIcon(for: result, entryId: item.entry.id)
                    Text(truncatedDestinationName(result.destination))
                        .font(FilmCanFont.label(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                        .help(destinationHoverText(for: result))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)

            Spacer(minLength: 0)
            if let presetLabel = presetLabel(for: item.entry) {
                Text(presetLabel)
                    .font(FilmCanFont.label(10))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(FilmCanTheme.brandYellow)
            }

            }
            .padding(.top, innerInset + 2)
            .padding(.horizontal, innerInset)
            .padding(.bottom, bottomPadding)
            .frame(maxHeight: .infinity)

            if result.success {
                historySticker(text: historyDateLabel(item.entry.endedAt))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 0)
            } else if result.wasPaused {
                Text("STOPPED")
                    .font(FilmCanFont.title(16))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .help(result.errorMessage ?? "Stopped by user")
            } else {
                Text("FAILED")
                    .font(FilmCanFont.title(16))
                    .foregroundColor(FilmCanTheme.brandRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .help(result.errorMessage ?? "")
            }
        }
        .frame(width: 200, height: 200)
        .contextMenu {
            Button("Use it again") { recallSettings(from: item.entry) }
            let destName = (result.destination as NSString).lastPathComponent
            let label = "Check data for \(destName)"
            let target = hashTarget(for: item.entry, result: result)
            let verifyDisabled = verifyDisabledReason(
                target: target,
                isVerifying: verifyingHashPaths.contains(target?.path ?? "")
            )
            Button(label) {
                guard let target else { return }
                runVerification(entry: item.entry, hashPath: target.path, roots: target.roots)
            }
            .disabled(
                target == nil
                    || verifyingHashPaths.contains(target?.path ?? "")
                    || !(target.map { canVerifyHashPath($0.path) } ?? false)
            )
            if let verifyDisabled {
                Button(verifyDisabled) {}
                    .disabled(true)
            }
            Divider()
            Button("Delete history card", role: .destructive) { deleteCandidate = item.entry }
        }
        .task(id: item.entry.id) {
            await loadHistoryCounts(entry: item.entry)
        }
    }

    private func runVerification(entry: TransferHistoryEntry, hashPath: String, roots: [String]) {
        if verifyingHashPaths.contains(hashPath) {
            return
        }
        verifyingHashPaths.insert(hashPath)
        let destinations = destinationsForHashPath(entry: entry, hashPath: hashPath)
        destinations.forEach { destination in
            verificationStatusByDestination[verificationKey(entryId: entry.id, destination: destination)] = .verifying
        }
        Task.detached(priority: .utility) {
            let report = HashListVerifier.verify(hashListPath: hashPath, rootsFallback: roots)
            await MainActor.run {
                verifyingHashPaths.remove(hashPath)
                let summary = VerificationSummary(
                    total: report?.total ?? 0,
                    missing: report?.missing ?? 0,
                    mismatched: report?.mismatched ?? 0,
                    failedLists: report == nil ? 1 : 0
                )
                let verificationSuccess = summary.missing == 0
                    && summary.mismatched == 0
                    && summary.failedLists == 0
                let status: VerificationStatus = verificationSuccess ? .success : .failure
                destinations.forEach { destination in
                    verificationStatusByDestination[verificationKey(entryId: entry.id, destination: destination)] = status
                }
                if let configId = entry.configId {
                    if verificationSuccess {
                        let verifiedDestinations = destinationsVerified(in: entry)
                        transferViewModel.setVerifiedDestinations(Set(verifiedDestinations), for: configId)
                    } else {
                        transferViewModel.clearVerifiedDestinations(for: configId)
                        transferViewModel.clearLastRun(for: configId)
                    }
                }
                if report == nil {
                    verificationSheet = VerificationAlert(
                        message: "Failed to read hash list.",
                        details: nil
                    )
                    return
                }
                if let details = verificationDetailsForHistory(from: hashPath, summary: summary) {
                    verificationSheet = VerificationAlert(
                        message: buildVerificationMessage(details),
                        details: details
                    )
                } else {
                    verificationSheet = VerificationAlert(
                        message: buildFallbackMessage(summary),
                        details: nil
                    )
                }
            }
        }
    }

    private func verificationDetailsForHistory(
        from hashPath: String,
        summary: VerificationSummary
    ) -> VerificationDetails? {
        guard let entry = appState.storage.transferHistory.first(where: { entry in
            if entry.hashListPath == hashPath { return true }
            return entry.results.contains { $0.hashListPath == hashPath }
        }) else { return nil }

        let verifiedDestinations = destinationsVerified(in: entry)
        let uncheckedDestinations = entry.destinations.filter { destination in
            !verifiedDestinations.contains(destination)
        }
        return VerificationDetails(
            summary: summary,
            verifiedDestinations: verifiedDestinations,
            uncheckedDestinations: uncheckedDestinations,
            logIncluded: logFileIncluded(in: verifiedDestinations, entry: entry),
            runDate: entry.endedAt
        )
    }

    private func buildFallbackMessage(_ summary: VerificationSummary) -> String {
        if summary.missing == 0 && summary.mismatched == 0 {
            return "Verified \(summary.total) file(s). All files match."
        }
        return "Verified \(summary.total) file(s). \(summary.missing) missing, \(summary.mismatched) mismatched."
    }

    private func buildVerificationMessage(_ details: VerificationDetails) -> String {
        let summary = details.summary
        if summary.missing == 0 && summary.mismatched == 0 {
            return "Verified \(summary.total) file(s). All files match."
        }
        return "Verified \(summary.total) file(s). \(summary.missing) missing, \(summary.mismatched) mismatched."
    }

    private var deleteHistoryMessage: String {
        guard let entry = deleteCandidate else { return "" }
        let date = entry.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "Delete history entry for \(displayConfigName(for: entry)) from \(date)?"
    }

    private func deleteHistoryEntry(_ entry: TransferHistoryEntry) {
        appState.storage.deleteHistoryEntry(entry)
    }

    private func matchesStatus(success: Bool) -> Bool {
        switch statusFilter {
        case .all:
            return true
        case .success:
            return success
        case .failed:
            return !success
        }
    }

    private func matchesSearch(entry: TransferHistoryEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let queryLower = query.lowercased()
        let candidates = [displayConfigName(for: entry)]
            + entry.sources.flatMap { pathCandidates(for: $0) }
            + entry.destinations.flatMap { pathCandidates(for: $0) }
        return candidates.contains { $0.lowercased().contains(queryLower) }
    }

    private func matchesSearch(item: DestinationItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let queryLower = query.lowercased()
        let candidates = [displayConfigName(for: item.entry)]
            + item.entry.sources.flatMap { pathCandidates(for: $0) }
            + pathCandidates(for: item.result.destination)
        return candidates.contains { $0.lowercased().contains(queryLower) }
    }

    private func matchesSearch(item: SourceItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let queryLower = query.lowercased()
        let candidates = [displayConfigName(for: item.entry)]
            + pathCandidates(for: item.source)
            + item.entry.destinations.flatMap { pathCandidates(for: $0) }
        return candidates.contains { $0.lowercased().contains(queryLower) }
    }

    private func pathCandidates(for path: String) -> [String] {
        let name = (path as NSString).lastPathComponent
        if name == path {
            return [name]
        }
        return [name, path]
    }

    private func sortEntries(_ entries: [TransferHistoryEntry]) -> [TransferHistoryEntry] {
        switch sortOption {
        case .mostRecent:
            return entries.sorted { $0.startedAt > $1.startedAt }
        case .leastRecent:
            return entries.sorted { $0.startedAt < $1.startedAt }
        case .alphabetical:
            return entries.sorted {
                displayConfigName(for: $0)
                    .localizedCaseInsensitiveCompare(displayConfigName(for: $1)) == .orderedAscending
            }
        }
    }

    private func sortDestinationItems(_ items: [DestinationItem]) -> [DestinationItem] {
        switch sortOption {
        case .mostRecent:
            return items.sorted { $0.entry.startedAt > $1.entry.startedAt }
        case .leastRecent:
            return items.sorted { $0.entry.startedAt < $1.entry.startedAt }
        case .alphabetical:
            return items.sorted {
                displayConfigName(for: $0.entry)
                    .localizedCaseInsensitiveCompare(displayConfigName(for: $1.entry)) == .orderedAscending
            }
        }
    }

    private func sortSourceItems(_ items: [SourceItem]) -> [SourceItem] {
        switch sortOption {
        case .mostRecent:
            return items.sorted { $0.entry.startedAt > $1.entry.startedAt }
        case .leastRecent:
            return items.sorted { $0.entry.startedAt < $1.entry.startedAt }
        case .alphabetical:
            return items.sorted {
                sourceDisplayName($0)
                    .localizedCaseInsensitiveCompare(sourceDisplayName($1)) == .orderedAscending
            }
        }
    }

    private func sourceLabelText(for sources: [String]) -> String {
        guard let first = sources.first else { return "No source" }
        let name = (first as NSString).lastPathComponent
        if sources.count > 1 {
            return "\(name) +\(sources.count - 1)"
        }
        return name
    }

    private func sourceDisplayName(_ item: SourceItem) -> String {
        let name = (item.source as NSString).lastPathComponent
        return name.isEmpty ? "Unknown source" : name
    }

    private func displayConfigName(for entry: TransferHistoryEntry) -> String {
        if let configId = entry.configId,
           let config = appState.storage.configurations.first(where: { $0.id == configId }) {
            return config.name
        }
        return entry.configName
    }

    private func presetLabel(for entry: TransferHistoryEntry) -> String? {
        let name = entry.options.organizationPresetName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return "Preset \(name)"
        }
        return nil
    }

    private func historySummaryText(for result: TransferResultRecord) -> String {
        let cached = historyCounts[result.id]
        let summary = TransferResultSummary(
            record: result,
            counts: cached.map { (transferred: $0.transferred, skipped: $0.skipped) }
        )
        return summary.historySummaryLine
    }

    private enum VerificationStatus {
        case success
        case failure
        case verifying
    }

    private func destinationStatusIcon(for result: TransferResultRecord, entryId: UUID) -> some View {
        let key = verificationKey(entryId: entryId, destination: result.destination)
        let status = verificationStatusByDestination[key]
            ?? (result.success ? .success : .failure)
        let isVerifying = status == .verifying
        let isSuccess = status == .success
        return Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isSuccess ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed)
            .rotationEffect(.degrees(isVerifying ? 360 : 0))
            .animation(
                isVerifying ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                value: isVerifying
            )
    }

    private func destinationsForHashPath(entry: TransferHistoryEntry, hashPath: String) -> [String] {
        if entry.hashListPath == hashPath {
            return entry.destinations
        }
        return entry.results.compactMap { result in
            result.hashListPath == hashPath ? result.destination : nil
        }
    }

    private func canVerifyHashPath(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func verifyDisabledReason(
        target: (path: String, roots: [String])?,
        isVerifying: Bool
    ) -> String? {
        if isVerifying {
            return "Verification already running"
        }
        guard let target else {
            return "Hash list missing for this backup"
        }
        if !canVerifyHashPath(target.path) {
            return "Hash list not found on disk"
        }
        return nil
    }

    private func verificationKey(entryId: UUID, destination: String) -> String {
        "\(entryId.uuidString)|\(destination)"
    }

    private func truncatedDestinationName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        guard name.count > 12 else { return name }
        let suffix = String(name.suffix(5))
        let prefixLength = min(9, max(1, name.count - 5))
        let prefix = String(name.prefix(prefixLength))
        return "\(prefix) [...] \(suffix)"
    }

    private func destinationHoverText(for result: TransferResultRecord) -> String {
        historySummaryText(for: result)
    }

    private func sourceHoverText(for entry: TransferHistoryEntry) -> String {
        let fileCounts = entry.results.map {
            let files = $0.visibleFilesTransferred ?? $0.filesTransferred
            let skipped = $0.visibleFilesSkipped ?? $0.filesSkipped
            return max(files + skipped, 0)
        }
        let totalFiles = fileCounts.max() ?? 0
        let totalBytes = entry.results.map { $0.bytesTransferred }.max() ?? 0
        let fileLabel = totalFiles == 1 ? "1 file" : "\(totalFiles) files"
        let bytesLabel = FilmCanFormatters.bytes(totalBytes, style: .decimal)
        return "\(fileLabel) · \(bytesLabel)"
    }

    private func hashTarget(for entry: TransferHistoryEntry, result: TransferResultRecord) -> (path: String, roots: [String])? {
        if let path = result.hashListPath {
            return (path, result.hashRoots)
        }
        if let path = entry.hashListPath {
            return (path, entry.hashRoots)
        }
        return nil
    }

    private func historyDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy HH:mm"
        return formatter.string(from: date)
    }

    private func historySticker(text: String) -> some View {
        Text(text)
            .font(FilmCanFont.label(10))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(FilmCanTheme.textPrimary)
            .padding(.horizontal, 6)
            .frame(width: 100, height: 31)
            .background(FilmCanTheme.brandGreen)
            .clipShape(TopRoundedRectangle(radius: 10))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private struct HistoryCounts {
        let transferred: Int
        let skipped: Int
    }

    private func loadHistoryCounts(entry: TransferHistoryEntry) async {
        for result in entry.results {
            if historyCounts[result.id] != nil { continue }
            guard let logFile = result.logFilePath else { continue }
            if let counts = await computeHistoryCounts(logFile: logFile, sources: entry.sources) {
                await MainActor.run {
                    historyCounts[result.id] = counts
                }
            }
        }
    }

    private func computeHistoryCounts(logFile: String, sources: [String]) async -> HistoryCounts? {
        await Task.detached(priority: .utility) {
            guard let content = try? String(contentsOfFile: logFile, encoding: .utf8) else { return nil }
            var visibleTransferred = 0
            var sawItemize = false

            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let (code, path) = Self.extractItemizedPath(from: trimmed) else { continue }
                sawItemize = true
                guard Self.shouldRecordItemizedFile(code) else { continue }
                let cleaned = Self.cleanItemizedPath(path)
                guard !cleaned.isEmpty else { continue }
                if Self.isHiddenPath(cleaned) { continue }
                visibleTransferred += 1
            }

            guard sawItemize else { return nil }
            let visibleTotal = Self.countVisibleFilesSync(sources: sources)
            let skipped = max(0, visibleTotal - visibleTransferred)
            return HistoryCounts(transferred: visibleTransferred, skipped: skipped)
        }.value
    }

    private nonisolated static func extractItemizedPath(from line: String) -> (code: String, path: String)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        var cursor = line.startIndex
        for token in tokens {
            guard let range = line.range(of: token, range: cursor..<line.endIndex) else { continue }
            if isItemizeCode(String(token)) {
                let code = String(token)
                let pathStart = line.index(range.upperBound, offsetBy: 1, limitedBy: line.endIndex) ?? line.endIndex
                let path = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
                return (code, path)
            }
            cursor = range.upperBound
        }
        return nil
    }

    private nonisolated static func isItemizeCode(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        let prefixes: Set<Character> = [">", "<", "c", "h", ".", "*"]
        let types: Set<Character> = ["f", "d", "L", "D", "S", "."]
        return prefixes.contains(chars[0]) && types.contains(chars[1])
    }

    private nonisolated static func shouldRecordItemizedFile(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        guard chars[1] == "f" else { return false }
        return chars[0] == ">" || chars[0] == "c"
    }

    private nonisolated static func cleanItemizedPath(_ raw: String) -> String {
        var path = raw
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[..<arrowRange.lowerBound])
        }
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func countVisibleFilesSync(sources: [String]) -> Int {
        var total = 0
        let fm = FileManager.default
        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if !isHiddenPath(source) { total += 1 }
                continue
            }
            let rootURL = URL(fileURLWithPath: source)
            let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   values.isDirectory == true {
                    continue
                }
                let path = fileURL.standardizedFileURL.path
                if isHiddenPath(path) { continue }
                if fileURL.lastPathComponent == ".DS_Store" { continue }
                total += 1
            }
        }
        return total
    }

    private nonisolated static func isHiddenPath(_ path: String) -> Bool {
        if FilmCanPaths.isHidden(path) { return true }
        let components = path.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }

    private enum HistoryStatusFilter: String, CaseIterable, Identifiable {
        case all
        case success
        case failed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:
                return "All"
            case .success:
                return "Success"
            case .failed:
                return "Failed"
            }
        }
    }

    private enum HistorySortOption: String, CaseIterable, Identifiable {
        case mostRecent
        case leastRecent
        case alphabetical

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mostRecent:
                return "Most recent"
            case .leastRecent:
                return "Least recent"
            case .alphabetical:
                return "Alphabetical"
            }
        }
    }

    private struct VerificationAlertSheet: View {
        let alert: VerificationAlert
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verification")
                    .font(FilmCanFont.title(16))
                if let details = alert.details {
                    verificationDetails(details)
                } else {
                    Text(alert.message)
                        .font(FilmCanFont.body(12))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
                HStack {
                    Spacer()
                    Button("OK") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 420)
        }

        @ViewBuilder
        private func verificationDetails(_ details: VerificationDetails) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                if details.summary.missing == 0 && details.summary.mismatched == 0 {
                    Text("Verified \(details.summary.total) file(s). All files match.")
                } else {
                    Text("Verified \(details.summary.total) file(s). \(details.summary.missing) missing, \(details.summary.mismatched) mismatched.")
                }

                if !details.verifiedDestinations.isEmpty {
                    let checked = details.verifiedDestinations
                        .map { ($0 as NSString).lastPathComponent }
                        .joined(separator: ", ")
                    Text("Checked: \(checked)")
                }

                if !details.uncheckedDestinations.isEmpty {
                    let unchecked = details.uncheckedDestinations
                        .map { ($0 as NSString).lastPathComponent }
                        .joined(separator: ", ")
                    Text("Not checked: \(unchecked)")
                        .foregroundColor(.secondary)
                }

                Text("Based on last run: \(formatDate(details.runDate))")
                    .foregroundColor(.secondary)

                if details.summary.failedLists > 0 {
                    Text("\(details.summary.failedLists) hash list(s) could not be read.")
                        .foregroundColor(.secondary)
                }
            }
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    private func destinationsVerified(in entry: TransferHistoryEntry) -> [String] {
        if entry.hashListPath != nil {
            return entry.destinations
        }
        let perDestination = entry.results.compactMap { result in
            result.hashListPath != nil ? result.destination : nil
        }
        return Array(Set(perDestination)).sorted()
    }

    private func logFileIncluded(in destinations: [String], entry: TransferHistoryEntry) -> Bool {
        let logPaths = entry.results.compactMap { $0.logFilePath }
        guard !logPaths.isEmpty, !destinations.isEmpty else { return false }
        for logPath in logPaths {
            for destination in destinations {
                if logPath == destination || logPath.hasPrefix(destination + "/") {
                    return true
                }
            }
        }
        return false
    }

    private func resumeBackup(for entry: TransferHistoryEntry) {
        guard let configId = entry.configId,
              let config = appState.storage.configurations.first(where: { $0.id == configId }) else {
            resumeError = "This backup no longer exists."
            return
        }
        appState.selectConfig(config)
        Task {
            await transferViewModel.startTransfer(config: config)
        }
    }
    
    private func recallSettings(from entry: TransferHistoryEntry) {
        var config = BackupConfiguration.empty
        let baseName = "\(entry.configName) (from history)"
        config.name = uniqueConfigName(baseName)
        config.sourcePaths = entry.sources
        config.destinationPaths = entry.destinations
        config.copyFolderContents = entry.options.copyFolderContents
        config.runInParallel = entry.options.runInParallel
        config.logEnabled = entry.options.logEnabled
        if let policy = OrganizationPreset.DuplicatePolicy(rawValue: entry.options.duplicatePolicy) {
            config.duplicatePolicy = policy
        }
        config.duplicateCounterTemplate = entry.options.duplicateCounterTemplate

        var options = RsyncOptions()
        options.copyEngine = CopyEngine(rawValue: entry.options.copyEngine) ?? .rsync
        options.useChecksum = entry.options.useChecksum
        options.postVerify = entry.options.postVerify
        options.onlyCopyChanged = entry.options.onlyCopyChanged
        options.reuseOrganizedFiles = false
        options.allowResume = entry.options.allowResume
        options.delete = entry.options.deleteExtraFiles
        options.inplace = entry.options.updateInPlace
        options.customArgs = entry.options.customArgs
        config.rsyncOptions = options

        if let presetName = entry.options.organizationPresetName {
            if let preset = appState.storage.organizationPresets.first(where: { $0.name == presetName }) {
                config.selectedOrganizationPresetId = preset.id
            }
        }

        appState.storage.add(config)
        appState.selectConfig(config)
    }
    
    private func uniqueConfigName(_ base: String) -> String {
        let existing = Set(appState.storage.configurations.map { $0.name })
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

private struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let tl = radius
        let tr = radius
        let bl: CGFloat = 0
        let br: CGFloat = 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}
