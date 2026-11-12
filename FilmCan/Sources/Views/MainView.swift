import SwiftUI
import AppKit

extension Notification.Name {
    static let filmCanShowCatalogPane = Notification.Name("filmCanShowCatalogPane")
}

struct MainView: View {
    enum RightPane { case none, history, catalog }

    @EnvironmentObject var appState: AppState
    @StateObject private var listViewModel = BackupListViewModel()
    @ObservedObject private var transferViewModel = TransferViewModel.shared
    @ObservedObject private var storage = ConfigurationStorage.shared
    @ObservedObject private var catalogStore = MediaCatalogStore.shared
    @State private var rightPane: RightPane = .history
    @State private var demoError: String?
    @State private var catalogDragStartWidth: Double?
    @AppStorage("catalogPaneWidth") private var catalogPaneWidth: Double = 380
    @State private var showQuickTour: Bool = false
    @State private var quickTourIndex: Int = 0
    @State private var quickTourNameConfirmed: Bool = false
    @State private var quickTourInitialBackupIds: Set<UUID> = []
    @State private var lastTourCanAdvance: Bool = false
    @State private var showDonationPrompt: Bool = false
    @State private var donationPromptTransferCount: Int = 0
    @State private var pendingDonationPromptCheck: Bool = false
    @State private var workspaceObservers: [NSObjectProtocol] = []
    @State private var hostWindow: NSWindow?
    @AppStorage("didShowQuickTour") private var didShowQuickTour: Bool = false
    @AppStorage("donationPromptSuppressed") private var donationPromptSuppressed: Bool = false
    @AppStorage("donationLastPromptCount") private var donationLastPromptCount: Int = 0
    @AppStorage("appearanceAccentHex") private var appearanceAccentHex: String = AppearanceDefaults.accentHex
    @AppStorage("appearanceAccentMode") private var appearanceAccentMode: String = AppearanceDefaults.accentMode
    @AppStorage("appearanceSuccessHex") private var appearanceSuccessHex: String = AppearanceDefaults.successHex
    @AppStorage("appearanceBackgroundHex") private var appearanceBackgroundHex: String = AppearanceDefaults.backgroundHex
    @AppStorage("appearanceSidebarHex") private var appearanceSidebarHex: String = AppearanceDefaults.sidebarHex
    @AppStorage("appearancePanelHex") private var appearancePanelHex: String = AppearanceDefaults.panelHex
    @AppStorage("appearanceTextHex") private var appearanceTextHex: String = AppearanceDefaults.textHex
    
    var body: some View {
        decoratedContent
            .background(MainWindowReader(window: $hostWindow))
            .onAppear {
                if !didShowQuickTour {
                    startTour()
                }
                registerDriveObservers()
                scheduleDonationPromptCheck()
            }
            .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
                NotificationCenter.default.post(name: .filmCanDriveListChanged, object: nil)
            }
            .onChange(of: canAdvanceTourStep) { completed in
                if showQuickTour && completed && !lastTourCanAdvance && currentTourStep.requirement != .none {
                    if currentTourStep.autoAdvance {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            advanceTour(by: 1)
                        }
                    }
                }
                lastTourCanAdvance = completed
            }
            .onChange(of: quickTourIndex) { _ in
                lastTourCanAdvance = canAdvanceTourStep
                updateTourSideEffects()
            }
            .onChange(of: showQuickTour) { _ in
                lastTourCanAdvance = canAdvanceTourStep
                updateTourSideEffects()
                if !showQuickTour && pendingDonationPromptCheck {
                    pendingDonationPromptCheck = false
                    evaluateDonationPrompt()
                }
            }
            .onChange(of: storage.configurations) { _ in
                guard showQuickTour, currentTourStep.requirement == .createdBackup else { return }
                if canAdvanceTourStep {
                    advanceTour(by: 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .filmCanShowCatalogPane)) { _ in
                guard MainWindowTarget.shouldHandle(in: hostWindow), rightPane != .catalog else { return }
                withAnimation(.easeInOut(duration: 0.2)) { rightPane = .catalog }
            }
            .onReceive(NotificationCenter.default.publisher(for: .filmCanRestartTour)) { _ in
                guard MainWindowTarget.shouldHandle(in: hostWindow) else { return }
                didShowQuickTour = false
                startTour()
            }
            .onReceive(NotificationCenter.default.publisher(for: .filmCanTourNameConfirmed)) { _ in
                guard showQuickTour, currentTourStep.requirement == .renamedBackup else { return }
                let name = selectedConfig?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                quickTourNameConfirmed = !name.isEmpty
            }
            .onReceive(NotificationCenter.default.publisher(for: .filmCanTourNameSubmitted)) { _ in
                guard showQuickTour, currentTourStep.requirement == .renamedBackup else { return }
                let name = selectedConfig?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return }
                quickTourNameConfirmed = true
                advanceTour(by: 1)
            }
            .sheet(isPresented: $showDonationPrompt, onDismiss: {
                recordDonationSkipIfNeeded()
            }) {
                DonationPromptView(
                    transferCount: donationPromptTransferCount,
                    onSkip: handleDonationSkip,
                    onDonated: handleDonationDonated
                )
            }
    }

    private var baseContent: some View {
        mainContent
            .background(FilmCanTheme.backgroundGradient)
            .background(WindowTitleSetter(title: ""))
    }

    private var insetContent: some View {
        baseContent.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                topBar
                StorageErrorBanner(
                    loadError: storage.lastLoadError,
                    saveError: storage.lastSaveError
                )
            }
        }
    }

    private var overlayContent: some View {
        insetContent
            .coordinateSpace(name: TourCoordinateSpace.name)
            .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
                quickTourOverlay(anchors: anchors)
            }
    }

    private var decoratedContent: some View {
        overlayContent
            .accentColor(FilmCanTheme.brandYellow)
            .textSelection(.enabled)
            .id(appearanceSignature)
    }

    @ViewBuilder
    private var mainContent: some View {
        HStack(spacing: 0) {
            editorPanel
            switch rightPane {
            case .none:
                EmptyView()
            case .history:
                Divider()
                    .ignoresSafeArea()
                TransferHistoryView(transferViewModel: transferViewModel)
                    .frame(width: 250)
                    .transition(.move(edge: .trailing))
                    .tourAnchor("historyPanel")
            case .catalog:
                Divider()
                    .ignoresSafeArea()
                catalogPane
                    .transition(.move(edge: .trailing))
            }
        }
    }

    private var clampedCatalogWidth: CGFloat {
        CGFloat(min(max(catalogPaneWidth, 250), 420))
    }

    private var catalogPane: some View {
        VStack(spacing: 0) {
            Text("Catalog — all movies")
                .font(FCType.itemTitle)
                .foregroundColor(FilmCanTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider().background(FilmCanTheme.cardStroke)
            CatalogView(paneWidth: clampedCatalogWidth)
                .environmentObject(catalogStore)
        }
        .frame(width: clampedCatalogWidth)
        .background(FilmCanTheme.sidebar)
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = catalogDragStartWidth ?? Double(clampedCatalogWidth)
                            catalogDragStartWidth = start
                            catalogPaneWidth = min(max(start - Double(value.translation.width), 250), 420)
                        }
                        .onEnded { _ in catalogDragStartWidth = nil }
                )
                .accessibilityLabel("Resize catalog pane")
        }
    }

    private func togglePane(_ pane: RightPane) {
        withAnimation(.easeInOut(duration: 0.2)) {
            rightPane = (rightPane == pane) ? .none : pane
        }
    }

    @ViewBuilder
    private var editorPanel: some View {
        if let configId = appState.selectedConfigId,
           let config = appState.storage.configurations.first(where: { $0.id == configId }) {
            VStack(spacing: 0) {
                if DemoSession.isDemo(config.id) {
                    DemoBanner(canStop: !transferViewModel.isTransferActive(for: config.id), onStop: stopDemo)
                }
                BackupEditorView(
                    config: config,
                    transferViewModel: transferViewModel,
                    isHistoryVisible: rightPane != .none,
                    rightPaneWidth: rightPane == .catalog ? clampedCatalogWidth : 250,
                    onToggleHistory: { togglePane(.history) }
                )
                .id(config.id)
            }
        } else {
            emptyStateView
        }
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            BackupListView(
                viewModel: listViewModel,
                transferViewModel: transferViewModel,
                appState: appState,
                trailingInset: 0
            )

            HStack(spacing: 4) {
                historyButton
                catalogButton
            }
            .padding(.trailing, 8)
        }
        .frame(height: 44)
        .background(FilmCanTheme.sidebar)
        .overlay(alignment: .bottom) {
            Divider()
                .background(FilmCanTheme.cardStroke)
        }
    }

    @ViewBuilder
    private func quickTourOverlay(anchors: [String: CGRect]) -> some View {
        if showQuickTour {
            QuickTourView(
                isPresented: $showQuickTour,
                didShowTour: $didShowQuickTour,
                steps: QuickTourStep.defaultSteps,
                currentIndex: quickTourIndex,
                canAdvance: canAdvanceTourStep,
                anchors: anchors,
                onBack: { advanceTour(by: -1) },
                onNext: { advanceTour(by: 1) },
                onDone: finishTour,
                onSkip: { showQuickTour = false }
            )
        }
    }

    private var appearanceSignature: String {
        [
            appearanceAccentHex,
            appearanceAccentMode,
            appearanceSuccessHex,
            appearanceBackgroundHex,
            appearanceSidebarHex,
            appearancePanelHex,
            appearanceTextHex
        ].joined(separator: "|")
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: appState.storage.configurations.isEmpty ? "externaldrive.badge.questionmark" : "externaldrive.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(FilmCanTheme.brandYellow.opacity(0.7))
            
            VStack(spacing: 8) {
                Text(appState.storage.configurations.isEmpty ? "No Movies Yet" : "No Movie Selected")
                    .font(FCType.display)
                Text(appState.storage.configurations.isEmpty
                    ? "Create your first movie to get started"
                    : "Select a movie tab above or create a new one")
                    .font(FilmCanFont.body(15))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            HoverButton(action: { _ = appState.createNewConfig() }) {
                Label(appState.storage.configurations.isEmpty ? "Create First Movie" : "Create New Movie", systemImage: "plus.circle.fill")
                    .font(FCType.cardTitle)
                    .foregroundColor(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(FilmCanTheme.brandYellow)
            .controlSize(.large)

            if !DemoSession.isRunning(storage: appState.storage) {
                VStack(spacing: 6) {
                    Button("Try with made-up cards", action: startDemo)
                        .controlSize(.large)
                    Text("Creates a demo movie with two made-up cards and two made-up drives, as folders on this Mac. The copy is real. \u{201C}Stop the demo\u{201D} removes everything.")
                        .font(FCType.meta)
                        .foregroundColor(FilmCanTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(FilmCanTheme.backgroundGradient)
        .alert("The demo could not be prepared", isPresented: Binding(
            get: { demoError != nil }, set: { if !$0 { demoError = nil } })
        ) {
            Button("OK", role: .cancel) { demoError = nil }
        } message: {
            Text(demoError ?? "")
        }
    }

    private func startDemo() {
        do {
            let config = try DemoSession.start(storage: appState.storage, catalog: MediaCatalogStore.shared,
                                               rollStore: RollNumberingStore.shared,
                                               isCopying: { transferViewModel.isTransferActive(for: $0) })
            appState.selectedConfigId = config.id
        } catch {
            demoError = error.localizedDescription
        }
    }

    private func stopDemo() {
        let demoId = DemoSession.demoConfigId()
        let stopped = DemoSession.stop(storage: appState.storage, catalog: MediaCatalogStore.shared,
                                       rollStore: RollNumberingStore.shared,
                                       isCopying: { transferViewModel.isTransferActive(for: $0) })
        if stopped, appState.selectedConfigId == demoId {
            appState.selectedConfigId = appState.storage.configurations.first?.id
        }
    }

    private func registerDriveObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let postRefresh: (Notification) -> Void = { _ in
            NotificationCenter.default.post(name: .filmCanDriveListChanged, object: nil)
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main, using: postRefresh))
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main, using: postRefresh))
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didRenameVolumeNotification, object: nil, queue: .main, using: postRefresh))
    }

    private var catalogButton: some View {
        let atRisk = !MediaCatalog.atRisk(catalogStore.rolls).isEmpty
        let active = rightPane == .catalog
        return Button(action: { togglePane(.catalog) }) {
            Image(systemName: active ? "books.vertical.fill" : "books.vertical")
                .foregroundColor(active ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                .font(.system(size: 13, weight: .semibold))
                .padding(6)
        }
        .frame(width: 28, height: 28)
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if atRisk {
                Circle().fill(FilmCanTheme.brandOrange).frame(width: 7, height: 7)
            }
        }
        .help("Catalog — where every roll is")
        .accessibilityLabel(active ? "Hide catalog" : "Show catalog")
        .accessibilityValue(atRisk ? "Some rolls are on one drive only" : "")
    }

    private var historyButton: some View {
        let active = rightPane == .history
        return Button(action: { togglePane(.history) }) {
            Image(systemName: active ? "clock.fill" : "clock")
                .foregroundColor(active ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                .font(.system(size: 13, weight: .semibold))
                .padding(6)
        }
        .frame(width: 28, height: 28)
        .buttonStyle(.plain)
        .help("Transfer history")
        .accessibilityLabel(active ? "Hide history" : "Show history")
        .tourAnchor("historyButton")
    }

    private var currentTourStep: QuickTourStep {
        QuickTourStep.defaultSteps[min(max(quickTourIndex, 0), QuickTourStep.defaultSteps.count - 1)]
    }

    private var selectedConfig: BackupConfiguration? {
        guard let configId = appState.selectedConfigId else { return nil }
        return appState.storage.configurations.first { $0.id == configId }
    }

    private var canAdvanceTourStep: Bool {
        switch currentTourStep.requirement {
        case .none:
            return true
        case .hasBackup:
            return !storage.configurations.isEmpty
        case .createdBackup:
            let ids = Set(storage.configurations.map { $0.id })
            return !ids.subtracting(quickTourInitialBackupIds).isEmpty
        case .renamedBackup:
            return quickTourNameConfirmed
        case .hasSource:
            return !(selectedConfig?.sourcePaths.isEmpty ?? true)
        case .hasDestination:
            return !(selectedConfig?.destinationPaths.isEmpty ?? true)
        }
    }

    private func startTour() {
        quickTourIndex = 0
        quickTourNameConfirmed = false
        quickTourInitialBackupIds = Set(storage.configurations.map { $0.id })
        showQuickTour = true
        lastTourCanAdvance = canAdvanceTourStep
        updateTourSideEffects()
    }

    private func finishTour() {
        didShowQuickTour = true
        showQuickTour = false
    }

    private func advanceTour(by delta: Int) {
        let next = min(max(quickTourIndex + delta, 0), QuickTourStep.defaultSteps.count - 1)
        quickTourIndex = next
        if currentTourStep.requirement == .renamedBackup {
            quickTourNameConfirmed = false
        }
        updateTourSideEffects()
    }

    private func updateTourSideEffects() {
        appState.activeTourTargetId = showQuickTour ? currentTourStep.targetId : nil
        if currentTourStep.targetId == "historyPanel", rightPane != .history {
            withAnimation(.easeInOut(duration: 0.2)) {
                rightPane = .history
            }
        }
    }

    private func scheduleDonationPromptCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if showQuickTour {
                pendingDonationPromptCheck = true
                return
            }
            evaluateDonationPrompt()
        }
    }

    private func evaluateDonationPrompt() {
        guard !donationPromptSuppressed else { return }
        let count = storage.totalTransferCount
        guard count >= 3 else { return }
        let shouldPrompt = (count == 3) || (count % 100 == 0)
        guard shouldPrompt else { return }
        guard donationLastPromptCount != count else { return }
        donationPromptTransferCount = count
        showDonationPrompt = true
    }

    private func recordDonationSkipIfNeeded() {
        guard donationPromptTransferCount > 0 else { return }
        donationLastPromptCount = donationPromptTransferCount
    }

    private func handleDonationSkip() {
        recordDonationSkipIfNeeded()
        showDonationPrompt = false
    }

    private func handleDonationDonated() {
        donationPromptSuppressed = true
        recordDonationSkipIfNeeded()
        showDonationPrompt = false
    }
}

// MARK: - Hover Button

struct HoverButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    @State private var isHovered = false
    
    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }
    
    var body: some View {
        Button(action: action, label: label)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Results View

struct ResultsView: View {
    let results: [TransferResult]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: results.allSatisfy { $0.success } ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(results.allSatisfy { $0.success } ? FilmCanTheme.brandGreen : .orange)
                Text(results.allSatisfy { $0.success } ? "Backup Complete" : "Backup Completed with Issues")
                    .font(.title2)
                Spacer()
            }
            .padding()
            
            List(results) { result in
                HStack {
                    Image(systemName: result.success ? "checkmark.circle" : "xmark.circle")
                        .foregroundColor(result.success ? FilmCanTheme.brandGreen : .red)
                    VStack(alignment: .leading) {
                        Text(result.destination)
                            .font(.headline)
                        Text(result.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(result.formattedDuration)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
