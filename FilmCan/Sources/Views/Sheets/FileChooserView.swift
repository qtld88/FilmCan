import SwiftUI
import AppKit

struct FileChooserView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: String = ""

    var body: some View {
        VStack {
            HStack {
                TextField(UIStrings.FolderPicker.pathPlaceholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                Button(UIStrings.FolderPicker.chooseButton) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                    }
                }
            }
            .padding()

            Spacer()

            HStack {
                Button(UIStrings.FolderPicker.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(UIStrings.FolderPicker.select) {
                    onSelect(path)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.isEmpty)
            }
            .padding()
        }
    }
}
