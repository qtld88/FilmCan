import SwiftUI
import Foundation
import AppKit

extension BackupEditorView {
    func startTransfer(confirmedDelete: Bool = false) {
        guard viewModel.validate() else { return }

        if viewModel.rsyncOptions.delete && !confirmedDelete {
            deleteWarningMessage = UIStrings.Alerts.deleteMessage
            showDeleteWarning = true
            return
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
