import SwiftUI
import Foundation

struct BackupEditorView: View {
    let config: BackupConfiguration
    @StateObject var viewModel: BackupEditorViewModel
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
    @State var isEditingPresetName = false
    @FocusState var isPresetNameFocused: Bool
    @State var isFolderDropTargeted = false
    @State var isRenameDropTargeted = false
    @State var showCopyOnlyPatterns = false
    @State var showIncludePatterns = false
    @State var showExcludePatterns = false
    @State var showRenameOnlyPatterns = false
    @State var isOptionsCollapsed = true
    @State var showEngineHelp = false
    @State var lastDriveRefresh: Date = .distantPast
    @State var driveRefreshCounter: Int = 0
    let optionToggleWidth: CGFloat = 60
    let optionMenuWidth: CGFloat = 140
    let optionTextWidth: CGFloat = 320
    let basicOptionTextWidth: CGFloat = 268
    let optionSpacing: CGFloat = 20
    let optionIconWidth: CGFloat = 32
    let historyPanelWidth: CGFloat = 250
    var isCustomEngine: Bool { viewModel.rsyncOptions.copyEngine == .custom }

    enum OptionsTab: String, CaseIterable, Identifiable {
        case basic = "Basic options"
        case source = "Source"
        case destinations = "Destinations"
        case logs = "Logs"
        case refinements = "Transfer refinements"

        var id: String { rawValue }

        var shortTitle: String {
            switch self {
            case .basic: return "Basic"
            case .source: return "Source"
            case .destinations: return "Destinations"
            case .logs: return "Logs"
            case .refinements: return "Rsync refinements"
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
        _viewModel = StateObject(wrappedValue: BackupEditorViewModel(config: config))
        self.transferViewModel = transferViewModel
        self.isHistoryVisible = isHistoryVisible
        self.onToggleHistory = onToggleHistory
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
        .sheet(isPresented: $showEngineHelp) {
            EngineHelpSheet()
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
        .onAppear {
            refreshPreview()
            viewModel.refreshAutoDetectedSources()
            viewModel.refreshAutoDetectedDestinations()
            viewModel.enforceCustomEngineDefaultsIfNeeded()
        }
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
        .onChange(of: viewModel.rsyncOptions.copyEngine) { engine in
            if engine == .custom && selectedOptionsTab == .refinements {
                selectedOptionsTab = .basic
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
            viewModel.syncFromStorage(updated)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmCanHotkeyRunNow)) { _ in
            guard !transferViewModel.isTransferring else { return }
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
                optionsSection()
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
}
