import SwiftUI
import Combine

@MainActor
final class OrganizationEditorModel: ObservableObject {
    private let viewModel: BackupEditorViewModel

    init(viewModel: BackupEditorViewModel) {
        self.viewModel = viewModel
    }

    var episode: String {
        get { viewModel.episode }
        set { objectWillChange.send(); viewModel.episode = newValue }
    }
    var day: String {
        get { viewModel.day }
        set { objectWillChange.send(); viewModel.day = newValue }
    }
    var unit: String {
        get { viewModel.unit }
        set { objectWillChange.send(); viewModel.unit = newValue }
    }
    var cameraFormat: String {
        get { viewModel.cameraFormat }
        set { objectWillChange.send(); viewModel.cameraFormat = newValue }
    }
    var cameraFolderTemplate: String {
        get { viewModel.cameraFolderTemplate }
        set { objectWillChange.send(); viewModel.cameraFolderTemplate = newValue }
    }
    var soundFolderTemplate: String {
        get { viewModel.soundFolderTemplate }
        set { objectWillChange.send(); viewModel.soundFolderTemplate = newValue }
    }
    var copyFolderContents: Bool {
        get { viewModel.copyFolderContents }
        set { objectWillChange.send(); viewModel.copyFolderContents = newValue }
    }
    var selectedOrganizationPresetId: UUID? {
        get { viewModel.selectedOrganizationPresetId }
        set { objectWillChange.send(); viewModel.selectedOrganizationPresetId = newValue }
    }
    var organizationPresets: [OrganizationPreset] { viewModel.organizationPresets }

    var selectedOrganizationPresetName: String? {
        guard let id = selectedOrganizationPresetId else { return nil }
        return organizationPresets.first(where: { $0.id == id })?.name
    }

    var isNetflixPresetSelected: Bool {
        selectedOrganizationPresetName == OrganizationPreset.netflixIngestName
    }

    /// True when the active preset's enabled templates contain `token`, so the
    /// matching shoot-metadata field is worth showing (mirrors Quick Copy).
    func activeTemplatesContain(_ token: String) -> Bool {
        guard let p = editingOrganizationPresetBinding?.wrappedValue else { return false }
        if p.useFolderTemplate, p.folderTemplate.contains(token) || p.soundFolderTemplate.contains(token) {
            return true
        }
        return p.useRenameTemplate && p.renameTemplate.contains(token)
    }

    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<OrganizationEditorModel, Value>) -> Binding<Value> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }

    var editingOrganizationPresetBinding: Binding<OrganizationPreset>? {
        if let binding = selectedPresetBinding { return binding }
        return Binding(
            get: { self.viewModel.localOrganizationPreset },
            set: { self.objectWillChange.send(); self.viewModel.localOrganizationPreset = $0 })
    }

    private var selectedPresetBinding: Binding<OrganizationPreset>? {
        guard let id = viewModel.selectedOrganizationPresetId,
              let current = viewModel.organizationPresets.first(where: { $0.id == id }) else { return nil }
        // Looked up by id on every read and write: the list is shared by every movie,
        // so a position can move under an open editor.
        return Binding(
            get: { self.viewModel.organizationPresets.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                self.objectWillChange.send()
                var presets = self.viewModel.organizationPresets
                if let index = presets.firstIndex(where: { $0.id == id }) {
                    presets[index] = newValue
                    self.viewModel.organizationPresets = presets
                }
            })
    }

    var tokenList: [(token: String, description: String)] {
        [
            ("{source}", "Original source name (file or folder)."),
            ("{sourceParent}", "Parent folder name of the source."),
            ("{sourceDriveName}", "Name of the drive containing the source."),
            ("{destinationDriveName}", "Name of the drive containing the destination."),
            ("{destination}", "Destination folder name."),
            ("{date}", "Today's date (YYYYMMDD)."),
            ("{movie}", "This movie's name."),
            ("{episode}", "Project / episode, from Shoot metadata."),
            ("{day}", "Shoot day, from Shoot metadata."),
            ("{unit}", "Unit, from Shoot metadata."),
            ("{cameraFormat}", "Camera format, from Shoot metadata."),
            ("{time}", "Current time (HHmmss)."),
            ("{datetime}", "Date and time (YYYYMMDD-HHmmss)."),
            ("{counter}", "Incrementing counter (001, 002, 003…)."),
            ("{filename}", "Source filename without extension."),
            ("{ext}", "File extension (includes the dot)."),
            ("{filecreationdate}", "File creation date (YYYYMMDD)."),
            ("{filemodifieddate}", "File modified date (YYYYMMDD).")
        ]
    }

    var defaultExcludePatterns: [String] { DefaultExcludes.patterns }

    func hasCustomFilterPatterns(_ preset: OrganizationPreset) -> Bool {
        SourceFilterMatching.hasCustomFilterPatterns(
            include: preset.includePatterns,
            exclude: preset.excludePatterns,
            copyOnly: preset.copyOnlyPatterns)
    }

    func excludePatternsBinding(_ presetBinding: Binding<OrganizationPreset>) -> Binding<[String]> {
        Binding(
            get: {
                let existing = presetBinding.excludePatterns.wrappedValue
                return existing.isEmpty ? self.defaultExcludePatterns : existing
            },
            set: { presetBinding.excludePatterns.wrappedValue = $0 })
    }

    func handleTokenDrop(providers: [NSItemProvider], into binding: Binding<String>) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let token = object as? String else { return }
                DispatchQueue.main.async { binding.wrappedValue += token }
            }
            return true
        }
        return false
    }
}
