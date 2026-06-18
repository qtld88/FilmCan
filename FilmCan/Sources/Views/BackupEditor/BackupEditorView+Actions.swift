import SwiftUI
import Foundation
import AppKit

extension BackupEditorView {
    private var isNetflixPresetSelected: Bool {
        viewModel.organizationPresets.first(where: { $0.id == viewModel.config.selectedOrganizationPresetId })?.name
            == OrganizationPreset.netflixIngestName
    }

    /// Rename source folders to satisfy Netflix naming (sanitize prohibited chars,
    /// dedupe), update the source list, and re-run.
    func autoFixNetflixNames() {
        let fm = FileManager.default
        var used = Set<String>()
        var newPaths: [String] = []
        for path in viewModel.sourcePaths {
            let url = URL(fileURLWithPath: path)
            let base = NetflixNameValidator.sanitize(url.lastPathComponent)
            var candidate = base
            var n = 1
            while used.contains(candidate) { candidate = "\(base)_\(String(format: "%03d", n))"; n += 1 }
            used.insert(candidate)
            if candidate != url.lastPathComponent {
                let dst = url.deletingLastPathComponent().appendingPathComponent(candidate)
                if (try? fm.moveItem(at: url, to: dst)) != nil {
                    newPaths.append(dst.path)
                } else {
                    newPaths.append(path)
                }
            } else {
                newPaths.append(path)
            }
        }
        viewModel.sourcePaths = newPaths
        startTransfer(skipNetflixValidation: true)
    }

    func startTransfer(confirmedDelete: Bool = false, skipNetflixValidation: Bool = false) {
        guard viewModel.validate() else { return }

        if !skipNetflixValidation && isNetflixPresetSelected {
            let rolls = viewModel.sourcePaths.map { ($0 as NSString).lastPathComponent }
            let issues = NetflixNameValidator.validate(rollNames: rolls)
            if !issues.isEmpty {
                netflixValidation = NetflixValidationInfo(issues: issues)
                return
            }
        }

        // Pre-flight space check
        let insufficientSpaceDestinations = checkSpaceBeforeTransfer()
        if !insufficientSpaceDestinations.isEmpty {
            spaceWarningMessage = buildSpaceWarningMessage(insufficientSpaceDestinations)
            showSpaceWarning = true
            return
        }
        
        beginTransfer()
    }

    func presentAddSourcePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                viewModel.addSource(url.path)
            }
        }
    }

    func presentAddDestinationPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addDestination(url.path)
        }
    }

    func refreshAllDriveData(force: Bool = false, includePreview: Bool = true) {
        let now = Date()
        if !force, now.timeIntervalSince(lastDriveRefresh) < 3 {
            return
        }
        lastDriveRefresh = now
        if includePreview {
            refreshPreview()
        }
        viewModel.refreshAutoDetectedSources()
        viewModel.refreshAutoDetectedSoundSources()
        viewModel.refreshAutoDetectedDestinations()
        driveRefreshCounter &+= 1
        if includePreview {
            transferViewModel.clearLastRun(for: viewModel.config.id)
        }
    }

    func beginTransfer() {
        Task {
            await transferViewModel.startTransfer(config: viewModel.config)
        }
    }

    func checkSpaceBeforeTransfer() -> [(destination: String, needed: Int64, available: Int64)] {
        var insufficient: [(String, Int64, Int64)] = []
        let requiredBytes = previewInfo.totalBytes
        
        guard requiredBytes > 0 else { return [] }
        
        for dest in viewModel.destinations {
            let capacity = DriveUtilities.capacity(for: dest)
            guard let available = capacity.available else { continue }
            if requiredBytes > available {
                insufficient.append((dest, requiredBytes, available))
            }
        }
        
        return insufficient
    }

    func buildSpaceWarningMessage(_ destinations: [(destination: String, needed: Int64, available: Int64)]) -> String {
        if destinations.count == 1 {
            let dest = destinations[0]
            let name = (dest.destination as NSString).lastPathComponent
            let neededStr = FilmCanFormatters.bytes(dest.needed, style: .file)
            let availableStr = FilmCanFormatters.bytes(dest.available, style: .file)
            return "Not enough space on \(name).\n\nNeeded: \(neededStr)\nAvailable: \(availableStr)\n\nThe backup may fail or be incomplete."
        } else {
            let names = destinations.map { ($0.destination as NSString).lastPathComponent }.joined(separator: ", ")
            return "Not enough space on \(destinations.count) destinations: \(names).\n\nThe backup may fail or be incomplete on these drives."
        }
    }
}
