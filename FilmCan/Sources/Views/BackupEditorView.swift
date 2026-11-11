import SwiftUI
import Foundation

struct BackupEditorView: View {
    let config: BackupConfiguration
    @StateObject var viewModel: BackupEditorViewModel
    @StateObject var organizationModel: OrganizationEditorModel
    @ObservedObject var transferViewModel: TransferViewModel
    let isHistoryVisible: Bool
    let onToggleHistory: () -> Void
    /// Closes the history / catalog pane: the movie settings panel takes its place.
    let onCloseRightPane: () -> Void
    @EnvironmentObject var appState: AppState
    /// The user asked for the movie settings panel (kept across movies and launches).
    @AppStorage("movieSettingsPanelOpen") var wantsMovieSettings = false



    @State var showFolderPicker = false
    @State var folderPickerMode: FolderPickerMode = .destination
    @State var previewInfo = PreviewInfo()
    @State var isEditingName = false
    @FocusState var isNameFocused: Bool
    @State var optionsAvailableWidth: CGFloat = 0
    @State var selectedOptionsTab: OptionsTab = .basic
    @State var showSpaceWarning = false
    @State var spaceWarningMessage = ""
    @State var showDeleteWarning = false
    @State var deleteWarningMessage = ""
    @State var showDuplicateNameWarning = false
    @State var duplicateNameWarningMessage = ""
    @State var isEditingPresetName = false
    @FocusState var isPresetNameFocused: Bool
    // The settings live in the side panel now and are always open there.
    @State var isOptionsCollapsed = false
    @State var hostWindow: NSWindow?
    @State var didLoadDestinations = false
    // Defer the options card mount one runloop after the editor appears so a
    // Film-tab switch (.id(config.id) rebuilds the whole editor) paints the
    // overview instantly; the heavy options tree fades in next frame.
    @State var optionsReady = false
    @State var netflixValidation: NetflixValidationInfo?
    @State var lastDriveRefresh: Date = .distantPast
    @State var driveRefreshCounter: Int = 0
    @ObservedObject private var driveCache = DriveInfoCache.shared
    let optionToggleWidth: CGFloat = 60
    let optionMenuWidth: CGFloat = 140
    let optionTextWidth: CGFloat = 320
    let basicOptionTextWidth: CGFloat = 268
    let optionSpacing: CGFloat = 20
    let optionIconWidth: CGFloat = 32
    let historyPanelWidth: CGFloat

    enum OptionsTab: String, CaseIterable, Identifiable {
        case basic = "Basic options"
        case source = "Source"
        case destinations = "Destinations"
        case logs = "Logs"

        var id: String { rawValue }

        var shortTitle: String {
            switch self {
            case .basic: return "Basic"
            case .source: return "Source"
            case .destinations: return "Destinations"
            case .logs: return "Logs"
            }
        }
    }
    
    enum FolderPickerMode {
        case destination, customLog
    }
    
    init(
        config: BackupConfiguration,
        transferViewModel: TransferViewModel,
        isHistoryVisible: Bool,
        rightPaneWidth: CGFloat = 250,
        onToggleHistory: @escaping () -> Void,
        onCloseRightPane: @escaping () -> Void = {}
    ) {
        self.onCloseRightPane = onCloseRightPane
        self.historyPanelWidth = rightPaneWidth
        self.config = config
        let vm = BackupEditorViewModel(config: config)
        _viewModel = StateObject(wrappedValue: vm)
        _organizationModel = StateObject(wrappedValue: OrganizationEditorModel(viewModel: vm))
        self.transferViewModel = transferViewModel
        self.isHistoryVisible = isHistoryVisible
        self.onToggleHistory = onToggleHistory
    }
    
    private func editorDidAppear() {
        DispatchQueue.main.async { optionsReady = true }
        refreshPreview()
        DriveInfoCache.shared.prime(viewModel.sourcePaths + viewModel.destinations)
        viewModel.refreshAutoDetectedSources()
        viewModel.refreshAutoDetectedSoundSources()
        viewModel.refreshAutoDetectedCards()
        viewModel.refreshAutoDetectedDestinations()
        viewModel.refreshGenericCards()
        viewModel.enforceCustomEngineDefaultsIfNeeded()
    }

    // Each binding captures the prompt it was built for, so a late dismissal write
    // answers that prompt (never a newer one) and the engine is always resumed.
    private var duplicatePromptBinding: Binding<DuplicatePrompt?> {
        let shown = transferViewModel.activeDuplicatePrompt?.id
        return Binding(
            get: { transferViewModel.activeDuplicatePrompt },
            set: { if $0 == nil, let shown { transferViewModel.dismissDuplicatePrompt(id: shown) } }
        )
    }

    private var rollIdentityPromptBinding: Binding<RollIdentityPrompt?> {
        let shown = transferViewModel.activeRollIdentityPrompt?.id
        return Binding(
            get: { transferViewModel.activeRollIdentityPrompt },
            set: { if $0 == nil, let shown { transferViewModel.dismissRollIdentityPrompt(id: shown) } }
        )
    }

    private var unreadablePromptBinding: Binding<Bool> {
        let shown = transferViewModel.pendingUnreadableFiles
        return Binding(
            get: { !transferViewModel.pendingUnreadableFiles.isEmpty },
            set: { if !$0 { transferViewModel.dismissUnreadablePrompt(paths: shown) } }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            editorContent(proxy: proxy)
        }
        .background(MainWindowReader(window: $hostWindow))
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(mode: folderPickerMode) { path in
                switch folderPickerMode {
                case .destination:
                    viewModel.addDestination(path)
                case .customLog:
                    viewModel.customLogPath = path
                }
            }
        }
        .sheet(item: duplicatePromptBinding) { prompt in
            DuplicatePromptSheet(
                prompt: prompt,
                onDecision: { action, applyToAll, counterTemplate in
                    transferViewModel.submitDuplicateResolution(
                        action: action,
                        applyToAll: applyToAll,
                        counterTemplate: counterTemplate
                    )
                },
                onCancel: {
                    transferViewModel.cancelRunFromDuplicatePrompt()
                }
            )
        }
        .sheet(item: rollIdentityPromptBinding) { prompt in
            RollIdentitySheet(prompt: prompt) { isResume in
                transferViewModel.submitRollIdentity(isResume: isResume)
            }
        }
        .sheet(item: $transferViewModel.alreadyBackedUp) { info in
            AlreadyBackedUpSheet(
                info: info,
                onVerify: { await transferViewModel.verifyAlreadyBackedUp($0) },
                onDone: { transferViewModel.alreadyBackedUp = nil }
            )
        }
        .sheet(isPresented: unreadablePromptBinding) {
            UnreadableFilesSheet(
                paths: transferViewModel.pendingUnreadableFiles,
                onContinue: { transferViewModel.resolveUnreadable(proceed: true) },
                onCancel: { transferViewModel.resolveUnreadable(proceed: false) }
            )
        }
        .sheet(item: $netflixValidation) { info in
            NetflixValidationSheet(
                info: info,
                onAutoFix: { netflixValidation = nil; autoFixNetflixNames() },
                onRunAnyway: { netflixValidation = nil; startTransfer(skipNetflixValidation: true) },
                onCancel: { netflixValidation = nil }
            )
        }
        .alert(UIStrings.Alerts.validationTitle, isPresented: $viewModel.showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.validationMessage)
        }
        .alert(UIStrings.Alerts.insufficientSpaceTitle, isPresented: $showSpaceWarning) {
            Button(UIStrings.Alerts.insufficientSpaceCancel, role: .cancel) {}
            Button(UIStrings.Alerts.insufficientSpaceContinue, role: .destructive) {
                beginTransfer()
            }
        } message: {
            Text(spaceWarningMessage)
        }
        .alert(UIStrings.Alerts.deleteTitle, isPresented: $showDeleteWarning) {
            Button(UIStrings.Alerts.deleteCancel, role: .cancel) {}
            Button(UIStrings.Alerts.deleteConfirm, role: .destructive) {
                startTransfer(confirmedDelete: true)
            }
        } message: {
            Text(deleteWarningMessage)
        }
        .alert("Sources with the same name", isPresented: $showDuplicateNameWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { startTransfer(skipDuplicateNameWarning: true) }
        } message: {
            Text(duplicateNameWarningMessage)
        }
        .onAppear(perform: editorDidAppear)
        .onChange(of: viewModel.sourcePaths) { _ in refreshPreview() }
        .onChange(of: viewModel.config.excludedSourcePaths) { _ in refreshPreview() }
        .onChange(of: viewModel.sourceAutoDetectEnabled) { enabled in
            if enabled {
                viewModel.refreshAutoDetectedSources()
            }
        }
        .onChange(of: viewModel.sourceAutoDetectPatterns) { _ in
            if viewModel.sourceAutoDetectEnabled {
                viewModel.refreshAutoDetectedSources()
            }
        }
        .onChange(of: viewModel.soundAutoDetectEnabled) { enabled in
            if enabled {
                viewModel.refreshAutoDetectedSoundSources()
            }
        }
        .onChange(of: viewModel.soundAutoDetectPatterns) { _ in
            if viewModel.soundAutoDetectEnabled {
                viewModel.refreshAutoDetectedSoundSources()
            }
        }
        .onChange(of: viewModel.soundDayFolderAutoDetect) { _ in
            if viewModel.soundAutoDetectEnabled {
                viewModel.refreshAutoDetectedSoundSources()
            }
            if viewModel.cardAutoDetectEnabled {
                viewModel.refreshAutoDetectedCards()
            }
        }
        .onChange(of: viewModel.cardAutoDetectEnabled) { enabled in
            if enabled {
                viewModel.refreshAutoDetectedCards()
            }
        }
        .onChange(of: viewModel.destinationAutoDetectEnabled) { enabled in
            if enabled {
                viewModel.refreshAutoDetectedDestinations()
            }
        }
        .onChange(of: viewModel.destinationAutoDetectPatterns) { _ in
            if viewModel.destinationAutoDetectEnabled {
                viewModel.refreshAutoDetectedDestinations()
            }
        }
        .onChange(of: viewModel.organizationPresets) { _ in
            viewModel.syncFromSelectedPresetIfNeeded()
        }
        .onChange(of: viewModel.selectedOrganizationPresetId) { _ in
            isEditingPresetName = false
            isPresetNameFocused = false
        }
        .onChange(of: config) { updated in
            PerfSignpost.region("onChange.config") {
                viewModel.syncFromStorage(updated)
            }
            organizationModel.objectWillChange.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyRunNow)) { _ in
            guard MainWindowTarget.shouldHandle(in: hostWindow) else { return }
            guard !transferViewModel.isTransferActive(for: viewModel.config.id) else { return }
            startTransfer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyAddSource)) { _ in
            guard MainWindowTarget.shouldHandle(in: hostWindow) else { return }
            presentAddSourcePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyAddDestination)) { _ in
            guard MainWindowTarget.shouldHandle(in: hostWindow) else { return }
            presentAddDestinationPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyRefreshDrives)) { _ in
            refreshAllDriveData(force: true, includePreview: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanDriveListChanged)) { _ in
            refreshAllDriveData(includePreview: false)
        }
    }

    @ViewBuilder
    private func editorContent(proxy: GeometryProxy) -> some View {
        let historyWidth = isHistoryVisible ? historyPanelWidth : 0
        let showsSettings = isMovieSettingsShown
        let settingsWidth = showsSettings ? MovieSettingsPanel.width(editorWidth: proxy.size.width) : 0
        let contentWidth = max(proxy.size.width - 48 - historyWidth - settingsWidth, 0)
        let isOverviewWide = contentWidth >= 750
        let contentPadding: CGFloat = contentWidth < 520 ? 12 : 24

        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    overviewSection(isWide: isOverviewWide)
                    movieSettingsLine
                }
                .padding(contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onTapGesture {
                if isEditingName {
                    confirmEditingName()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The settings sit beside the cards and drives, so the folder preview stays
            // in view and follows every change.
            if showsSettings {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        movieSettingsPanelHeader
                        if optionsReady {
                            optionsSection()
                        } else {
                            optionsMountPlaceholder
                        }
                    }
                    .padding(.vertical, 16)
                }
                .frame(width: settingsWidth)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FilmCanTheme.backgroundGradient)
        .onChange(of: isHistoryVisible) { visible in
            // One side pane at a time: opening history or the catalog closes the settings.
            if visible { wantsMovieSettings = false }
        }
    }

    var isMovieSettingsShown: Bool {
        MovieSettingsPanel.isShown(wantsOpen: wantsMovieSettings, otherPaneOpen: isHistoryVisible)
    }

    func openMovieSettings() {
        if isHistoryVisible { onCloseRightPane() }
        isOptionsCollapsed = false
        withAnimation(.easeInOut(duration: 0.2)) { wantsMovieSettings = true }
    }

    func closeMovieSettings() {
        withAnimation(.easeInOut(duration: 0.2)) { wantsMovieSettings = false }
    }

    /// The one quiet line left on the main screen: which settings the movie uses, and
    /// the way into them.
    private var movieSettingsLine: some View {
        Button {
            if isMovieSettingsShown { closeMovieSettings() } else { openMovieSettings() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .foregroundColor(FilmCanTheme.textSecondary)
                Text(SettingsWording.movieSettings)
                    .font(FCType.bodyStrong)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text(movieSettingsSummary)
                    .font(FCType.meta)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: isMovieSettingsShown ? "chevron.right" : "chevron.left")
                    .font(.caption)
                    .foregroundColor(FilmCanTheme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fcCardSurface(role: .settings)
        .tourAnchor("optionsTabs")
        .help("Copy, verification, folders and logs for this movie")
        .accessibilityLabel(SettingsWording.movieSettings)
    }

    private var movieSettingsPanelHeader: some View {
        HStack {
            Text(SettingsWording.movieSettings)
                .font(FCType.cardTitle)
                .foregroundColor(FilmCanTheme.textPrimary)
            Spacer()
            Button(action: closeMovieSettings) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close movie settings")
        }
        .padding(.horizontal, 16)
    }

    private var optionsMountPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(height: 80, alignment: .center)
    }
}
