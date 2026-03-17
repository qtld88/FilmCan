import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @AppStorage("defaultLogLocation") private var defaultLogLocation: String = "same"
    @AppStorage("notifyOnComplete") private var notifyOnComplete: Bool = true
    @AppStorage("notifyOnError") private var notifyOnError: Bool = true
    @AppStorage("ntfyEnabled") private var ntfyEnabled: Bool = false
    @AppStorage("ntfyURL") private var ntfyURL: String = ""
    @AppStorage("ntfyBearerToken") private var ntfyBearerToken: String = ""
    @AppStorage("ntfyTitleTemplate") private var ntfyTitleTemplate: String = "{source}'s backup to {destinations} for {movie} : {backupStatus}"
    @AppStorage("ntfyMessageTemplate") private var ntfyMessageTemplate: String = "{bytes} ({files} files) from {source} has been {backupAction} to {destination} in {duration}.\n{backupDetails}"
    @AppStorage("webhookEnabled") private var webhookEnabled: Bool = false
    @AppStorage("webhookURL") private var webhookURL: String = ""
    @AppStorage("webhookHeaders") private var webhookHeaders: String = ""
    @AppStorage("webhookSecret") private var webhookSecret: String = ""
    @AppStorage("historyRetentionLimit") private var historyRetentionLimit: Int = 200
    @AppStorage("appearanceAccentHex") private var appearanceAccentHex: String = AppearanceDefaults.accentHex
    @AppStorage("appearanceAccentMode") private var appearanceAccentMode: String = AppearanceDefaults.accentMode
    @AppStorage("appearanceSuccessHex") private var appearanceSuccessHex: String = AppearanceDefaults.successHex
    @AppStorage("appearanceBackgroundHex") private var appearanceBackgroundHex: String = AppearanceDefaults.backgroundHex
    @AppStorage("appearanceSidebarHex") private var appearanceSidebarHex: String = AppearanceDefaults.sidebarHex
    @AppStorage("appearancePanelHex") private var appearancePanelHex: String = AppearanceDefaults.panelHex
    @AppStorage("appearanceTextHex") private var appearanceTextHex: String = AppearanceDefaults.textHex

    var body: some View {
        TabView {
            AppearanceSettingsView(
                accentHex: $appearanceAccentHex,
                accentMode: $appearanceAccentMode,
                successHex: $appearanceSuccessHex,
                backgroundHex: $appearanceBackgroundHex,
                sidebarHex: $appearanceSidebarHex,
                panelHex: $appearancePanelHex,
                textHex: $appearanceTextHex
            )
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }

            NotificationsSettingsView(
                notifyOnComplete: $notifyOnComplete,
                notifyOnError: $notifyOnError
            )
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }

            PushSettingsView(
                ntfyEnabled: $ntfyEnabled,
                ntfyURL: $ntfyURL,
                ntfyBearerToken: $ntfyBearerToken,
                ntfyTitleTemplate: $ntfyTitleTemplate,
                ntfyMessageTemplate: $ntfyMessageTemplate,
                webhookEnabled: $webhookEnabled,
                webhookURL: $webhookURL,
                webhookHeaders: $webhookHeaders,
                legacyWebhookSecret: $webhookSecret
            )
            .tabItem {
                Label("Push", systemImage: "paperplane")
            }

            HistorySettingsView(
                historyRetentionLimit: $historyRetentionLimit
            )
            .tabItem {
                Label("History", systemImage: "clock")
            }

            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 660, idealHeight: 660)
        .modifier(SettingsWindowSizer())
    }
}

private struct SettingsWindowSizer: ViewModifier {
    @State private var didApply = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                applyWindowSize()
            }
    }

    private func applyWindowSize() {
        guard !didApply else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
            let newSize = NSSize(width: 440, height: 660)
            let frame = window.frame
            let newOrigin = NSPoint(
                x: frame.midX - newSize.width / 2,
                y: frame.midY - newSize.height / 2
            )
            window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
            didApply = true
        }
    }
}

struct AppearanceSettingsView: View {
    @Binding var accentHex: String
    @Binding var accentMode: String
    @Binding var successHex: String
    @Binding var backgroundHex: String
    @Binding var sidebarHex: String
    @Binding var panelHex: String
    @Binding var textHex: String
    @State private var lastAccentMode: String = ""

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Accent color", selection: $accentMode) {
                    Text("Kodak").tag("kodak")
                    Text("Fuji").tag("fuji")
                    Text("Sony").tag("sony")
                    Text("RED").tag("red")
                    Text("ARRI").tag("arri")
                    Text("System").tag("system")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.menu)
                colorRow(
                    title: "Accent color",
                    binding: $accentHex,
                    defaultHex: accentDefaultHex(for: accentMode),
                    isDisabled: accentMode == "system"
                )
                colorRow(
                    title: "Progress green",
                    binding: $successHex,
                    defaultHex: AppearanceDefaults.successHex
                )
                colorRow(
                    title: "Main background",
                    binding: $backgroundHex,
                    defaultHex: AppearanceDefaults.backgroundHex
                )
                colorRow(
                    title: "Left panel background",
                    binding: $sidebarHex,
                    defaultHex: AppearanceDefaults.sidebarHex
                )
                colorRow(
                    title: "Right panel background",
                    binding: $panelHex,
                    defaultHex: AppearanceDefaults.panelHex
                )
                colorRow(
                    title: "Font color",
                    binding: $textHex,
                    defaultHex: AppearanceDefaults.textHex
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
        .onAppear {
            if accentHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                accentHex = accentDefaultHex(for: accentMode)
            }
            lastAccentMode = accentMode
        }
        .onChange(of: accentMode) { newValue in
            applyPresetIfNeeded(previousMode: lastAccentMode, newMode: newValue)
            lastAccentMode = newValue
        }
    }

    private func colorBinding(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: {
                let value = hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue
                return Color(hexString: value)
            },
            set: { newColor in
                hex.wrappedValue = newColor.toHexString() ?? fallback
            }
        )
    }

    private func colorRow(
        title: String,
        binding: Binding<String>,
        defaultHex: String,
        isDisabled: Bool = false
    ) -> some View {
        let showReset = shouldShowReset(binding.wrappedValue, defaultHex: defaultHex)
        return HStack {
            ColorPicker(title, selection: colorBinding(binding, fallback: defaultHex))
                .disabled(isDisabled)
            if showReset && !isDisabled {
                Button(action: { binding.wrappedValue = defaultHex }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
    }

    private func accentDefaultHex(for mode: String) -> String {
        switch mode {
        case "fuji":
            return AppearanceDefaults.accentFuji
        case "sony":
            return AppearanceDefaults.accentSony
        case "red":
            return AppearanceDefaults.accentRed
        case "arri":
            return AppearanceDefaults.accentArri
        default:
            return AppearanceDefaults.accentKodak
        }
    }

    private func shouldShowReset(_ current: String, defaultHex: String) -> Bool {
        let lhs = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = defaultHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lhs.isEmpty else { return false }
        return lhs != rhs
    }

    private func applyPresetIfNeeded(previousMode: String, newMode: String) {
        guard previousMode != newMode else { return }
        switch newMode {
        case "kodak", "fuji", "sony", "red", "arri":
            accentHex = accentDefaultHex(for: newMode)
        default:
            break
        }
    }
}

struct NotificationsSettingsView: View {
    @Binding var notifyOnComplete: Bool
    @Binding var notifyOnError: Bool

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify on backup complete", isOn: $notifyOnComplete)
                    .tint(FilmCanTheme.toggleTint)
                Toggle("Notify on backup error", isOn: $notifyOnError)
                    .tint(FilmCanTheme.toggleTint)

                Button("Send test notification") {
                    NotificationService.shared.notify(
                        title: "FilmCan Test",
                        body: "If you can read this, banners are working."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
    }
}

struct PushSettingsView: View {
    @Binding var ntfyEnabled: Bool
    @Binding var ntfyURL: String
    @Binding var ntfyBearerToken: String
    @Binding var ntfyTitleTemplate: String
    @Binding var ntfyMessageTemplate: String
    @Binding var webhookEnabled: Bool
    @Binding var webhookURL: String
    @Binding var webhookHeaders: String
    @Binding var legacyWebhookSecret: String

    var body: some View {
        Form {
            Section("NTFY") {
                Toggle("Send ntfy push notifications", isOn: $ntfyEnabled)
                    .tint(FilmCanTheme.toggleTint)
                    .onChange(of: ntfyEnabled) { enabled in
                        if enabled {
                            NotificationService.shared.ensureAuthorized()
                        }
                    }
                TextField("topic URL address :", text: $ntfyURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!ntfyEnabled)
                SecureField("Bearer token :", text: $ntfyBearerToken)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!ntfyEnabled)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom notification title")
                        .font(FilmCanFont.body(12))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    TextEditor(text: $ntfyTitleTemplate)
                        .font(FilmCanFont.body(12))
                        .frame(minHeight: 44)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .disabled(!ntfyEnabled)
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleTokenDrop(providers: providers, into: $ntfyTitleTemplate)
                        }
                    Text("Custom message")
                        .font(FilmCanFont.body(12))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    TextEditor(text: $ntfyMessageTemplate)
                        .font(FilmCanFont.body(12))
                        .frame(minHeight: 80)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .disabled(!ntfyEnabled)
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleTokenDrop(providers: providers, into: $ntfyMessageTemplate)
                        }
                    TokenFlowLayout(spacing: 4) {
                        ForEach(tokenList, id: \.token) { entry in
                            NotificationTokenChip(text: entry.token)
                                .help(entry.description)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("• Create a free account at https://ntfy.sh (or self-hosted version).")
                    Text("• Click “Subscribe to topic”.")
                    Text("• Choose a unique topic name (avoid common names so others can’t read your notifications if you're on the free plan).")
                    Text("• Paste the topic URL here.")
                    Text("(Bearer tokens are available on the paid plan or self-hosted version.)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("Webhook") {
                Toggle("Send webhook notifications", isOn: $webhookEnabled)
                    .tint(FilmCanTheme.toggleTint)
                TextField("Webhook URL :", text: $webhookURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!webhookEnabled)
                Text("Custom headers (one per line)")
                    .font(FilmCanFont.body(12))
                    .foregroundColor(FilmCanTheme.textPrimary)
                TextEditor(text: $webhookHeaders)
                    .font(FilmCanFont.body(12))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .disabled(!webhookEnabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sends a JSON payload using the same title and message templates as ntfy.")
                    Text("Example: Authorization: Bearer <token>")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
        .onAppear {
            migrateLegacyWebhookSecretIfNeeded()
        }
    }

    private func migrateLegacyWebhookSecretIfNeeded() {
        let trimmedHeaders = webhookHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = legacyWebhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHeaders.isEmpty, !trimmedSecret.isEmpty else { return }
        webhookHeaders = "Authorization: Bearer \(trimmedSecret)"
        legacyWebhookSecret = ""
    }

    private var tokenList: [(token: String, description: String)] {
        [
            ("{movie}", "Backup name."),
            ("{source}", "First source name."),
            ("{destination}", "First destination name."),
            ("{sources}", "Quoted list of sources."),
            ("{destinations}", "Quoted list of destinations."),
            ("{backupAction}", "backed up / failed to back up / already in place."),
            ("{bytes}", "Total bytes copied (formatted)."),
            ("{files}", "Total file count."),
            ("{duration}", "Total transfer time."),
            ("{backupStatus}", "Status line."),
            ("{backupDetails}", "Details line.")
        ]
    }

    private func handleTokenDrop(
        providers: [NSItemProvider],
        into binding: Binding<String>
    ) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let token = object as? String else { return }
                    DispatchQueue.main.async {
                        binding.wrappedValue += token
                    }
                }
                return true
            }
        }
        return false
    }
}

private struct NotificationTokenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.disabled)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onDrag {
                NSItemProvider(object: text as NSString)
            }
    }
}

struct HistorySettingsView: View {
    @Binding var historyRetentionLimit: Int
    @ObservedObject private var storage = ConfigurationStorage.shared
    @State private var showPresetExport = false
    @State private var showPresetImport = false
    @State private var showHistoryExport = false
    @State private var showHistoryImport = false
    @State private var showHistoryExportPicker = false
    @State private var showHistoryImportPicker = false
    @State private var presetExportDocument = JSONExportDocument(data: Data())
    @State private var historyExportDocument = JSONExportDocument(data: Data())
    @State private var historyExportSelection = Set<UUID>()
    @State private var historyImportSelection = Set<UUID>()
    @State private var historyImportData: Data? = nil
    @State private var historyImportConfigurations: [BackupConfiguration] = []
    @State private var importErrorMessage: String? = nil

    var body: some View {
        Form {
            Section("History") {
                Stepper(value: $historyRetentionLimit, in: 10...1000, step: 10) {
                    Text("Keep last \(historyRetentionLimit) transfers")
                }
            }

            Section("Import & Export") {
                HStack {
                    Text("Presets")
                    Spacer()
                    Button("Export") {
                        do {
                            presetExportDocument = JSONExportDocument(data: try storage.exportPresetsData())
                            showPresetExport = true
                        } catch {
                            importErrorMessage = "Failed to export presets: \(error.localizedDescription)"
                        }
                    }
                    Button("Import") {
                        showPresetImport = true
                    }
                }

                HStack {
                    Text("Movies & History")
                    Spacer()
                    Button("Export") {
                        let movies = storage.configurations
                        guard !movies.isEmpty else {
                            importErrorMessage = "No movies available to export."
                            return
                        }
                        historyExportSelection = Set(movies.map(\.id))
                        showHistoryExportPicker = true
                    }
                    Button("Import") {
                        showHistoryImport = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
        .fileExporter(
            isPresented: $showPresetExport,
            document: presetExportDocument,
            contentType: .json,
            defaultFilename: "filmcan-presets"
        ) { result in
            if case .failure(let error) = result {
                importErrorMessage = "Failed to export presets: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $showHistoryExport,
            document: historyExportDocument,
            contentType: .json,
            defaultFilename: "filmcan-movies-history"
        ) { result in
            if case .failure(let error) = result {
                importErrorMessage = "Failed to export movies and history: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showPresetImport,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    try storage.importPresets(from: data)
                } catch {
                    importErrorMessage = "Failed to import presets: \(error.localizedDescription)"
                }
            case .failure(let error):
                importErrorMessage = "Failed to import presets: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showHistoryImport,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    let configs = try storage.decodeMoviesHistoryConfigurations(from: data)
                    guard !configs.isEmpty else {
                        importErrorMessage = "No movies found in the import file."
                        return
                    }
                    historyImportData = data
                    historyImportConfigurations = configs
                    historyImportSelection = Set(configs.map(\.id))
                    showHistoryImportPicker = true
                } catch {
                    importErrorMessage = "Failed to import movies and history: \(error.localizedDescription)"
                }
            case .failure(let error):
                importErrorMessage = "Failed to import movies and history: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showHistoryExportPicker) {
            MovieSelectionSheet(
                title: "Select movies to export",
                movies: storage.configurations,
                selection: $historyExportSelection,
                primaryActionTitle: "Export selected"
            ) {
                do {
                    historyExportDocument = JSONExportDocument(
                        data: try storage.exportMoviesHistoryData(for: historyExportSelection)
                    )
                    showHistoryExport = true
                    showHistoryExportPicker = false
                } catch {
                    importErrorMessage = "Failed to export movies and history: \(error.localizedDescription)"
                }
            } onCancel: {
                showHistoryExportPicker = false
            }
        }
        .sheet(isPresented: $showHistoryImportPicker) {
            MovieSelectionSheet(
                title: "Select movies to import",
                movies: historyImportConfigurations,
                selection: $historyImportSelection,
                primaryActionTitle: "Import selected"
            ) {
                guard let data = historyImportData else {
                    showHistoryImportPicker = false
                    return
                }
                do {
                    try storage.importMoviesHistory(
                        from: data,
                        retentionLimit: historyRetentionLimit,
                        selectedConfigIds: historyImportSelection
                    )
                    historyImportData = nil
                    historyImportConfigurations = []
                    showHistoryImportPicker = false
                } catch {
                    importErrorMessage = "Failed to import movies and history: \(error.localizedDescription)"
                }
            } onCancel: {
                historyImportData = nil
                historyImportConfigurations = []
                showHistoryImportPicker = false
            }
        }
        .alert("Import/Export Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct MovieSelectionSheet: View {
    let title: String
    let movies: [BackupConfiguration]
    @Binding var selection: Set<UUID>
    let primaryActionTitle: String
    let onPrimary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack(spacing: 8) {
                Button("Select all") {
                    selection = Set(movies.map(\.id))
                }
                Button("Select none") {
                    selection = []
                }
                Spacer()
            }

            List {
                ForEach(movies) { movie in
                    Toggle(isOn: binding(for: movie.id)) {
                        Text(movieDisplayName(movie))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button(primaryActionTitle) { onPrimary() }
                    .disabled(selection.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 480)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }

    private func movieDisplayName(_ movie: BackupConfiguration) -> String {
        let name = movie.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Backup" : name
    }
}

struct HotkeysSettingsView: View {
    var body: some View {
        Form {
            Section("Hotkeys") {
                HotkeyRow(title: "Start backup (Run Now)", shortcut: "⌘B")
                HotkeyRow(title: "Add a source", shortcut: "⌘S")
                HotkeyRow(title: "Add a destination", shortcut: "⌘D")
                HotkeyRow(title: "Refresh drives", shortcut: "⌘R")
            }
        }
        .formStyle(.grouped)
        .padding()
        .padding(.top, 30)
    }
}

struct HotkeyRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(FilmCanTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)

            Text("FilmCan")
                .font(.title)

            Text(buildNumber.map { "Version \(appVersion) (\($0))" } ?? "Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("A simple backup utility using rsync")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Text("Support FilmCan")
                    .font(.headline)

                Text("If FilmCan saves you time, please consider a donation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .center, spacing: 6) {
                    Text("Wire transfer (EU):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Name : Quentin Devillers")
                        .font(.caption)
                    Text("IBAN : DE35100110012624820251")
                        .font(.system(.caption, design: .monospaced))
                    Text("BIC : NTSBDEB1XXX")
                        .font(.system(.caption, design: .monospaced))
                    Text("Communication : FilmCan tips")
                        .font(.caption)
                }
                .frame(maxWidth: 360, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        donationButton(title: "Liberapay", url: "https://liberapay.com/FilmCan")
                        donationButton(title: "PayPal", url: "https://www.paypal.com/donate/?hosted_button_id=W5LXAQ8ENHUQN")
                        donationButton(title: "Buy Me a Coffee", url: "https://buymeacoffee.com/filmcan")
                        donationButton(title: "Ko-fi", url: "https://ko-fi.com/filmcan")
                        donationButton(title: "Tipeee", url: "https://en.tipeee.com/filmcan")
                        donationButton(title: "GitHub Sponsors", url: "https://github.com/sponsors/qtld88")
                    }
                    .padding(.bottom, 2)
                }
            }
            .padding(.top, 30)

            Spacer()
        }
        .padding()
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func donationButton(title: String, url: String) -> some View {
        Button(title) {
            guard let target = URL(string: url) else { return }
            openURL(target)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
