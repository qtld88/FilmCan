import SwiftUI
import Foundation

struct BackupEditorView: View {
    let config: BackupConfiguration
    @StateObject var viewModel: BackupEditorViewModel
    @StateObject var organizationModel: OrganizationEditorModel
    @ObservedObject var transferViewModel: TransferViewModel
    let isHistoryVisible: Bool
    let onToggleHistory: () -> Void
    @EnvironmentObject var appState: AppState



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
    @State var isOptionsCollapsed = true
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
    let historyPanelWidth: CGFloat = 250

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
        onToggleHistory: @escaping () -> Void
    ) {
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
        viewModel.refreshAutoDetectedDestinations()
        viewModel.enforceCustomEngineDefaultsIfNeeded()
    }

    var body: some View {
        GeometryReader { proxy in
            editorContent(proxy: proxy)
        }
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
        .sheet(item: $transferViewModel.activeDuplicatePrompt) { prompt in
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
        .sheet(item: $transferViewModel.activeRollIdentityPrompt) { prompt in
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
        .sheet(isPresented: Binding(
            get: { !transferViewModel.pendingUnreadableFiles.isEmpty },
            set: { if !$0 { transferViewModel.resolveUnreadable(proceed: false) } }
        )) {
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
            guard !transferViewModel.isTransferActive(for: viewModel.config.id) else { return }
            startTransfer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyAddSource)) { _ in
            presentAddSourcePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyAddDestination)) { _ in
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
        let contentWidth = max(proxy.size.width - 48 - historyWidth, 0)
        let isOverviewWide = contentWidth >= 750
        let contentPadding: CGFloat = contentWidth < 520 ? 12 : 24

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overviewSection(isWide: isOverviewWide)
                if optionsReady {
                    optionsSection()
                } else {
                    optionsMountPlaceholder
                }
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
        .background(FilmCanTheme.backgroundGradient)
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
