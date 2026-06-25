import SwiftUI

struct LogsOptionsView: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat

    var body: some View {
        LogSettingsView(
            logEnabled: Binding(
                get: { viewModel.logEnabled },
                set: { viewModel.logEnabled = $0 }
            ),
            logLocation: Binding(
                get: { viewModel.logLocation },
                set: { viewModel.logLocation = $0 }
            ),
            customLogPath: Binding(
                get: { viewModel.customLogPath },
                set: { viewModel.customLogPath = $0 }
            ),
            logFileNameTemplate: Binding(
                get: { viewModel.logFileNameTemplate },
                set: { viewModel.logFileNameTemplate = $0 }
            ),
            configName: viewModel.name,
            sampleDestination: viewModel.destinations.first ?? "Destination",
            showHeader: false
        )
    }
}
