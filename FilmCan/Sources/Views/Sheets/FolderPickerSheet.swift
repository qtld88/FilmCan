import SwiftUI

struct FolderPickerSheet: View {
    let mode: BackupEditorView.FolderPickerMode
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(UIStrings.FolderPicker.title)
                .font(.headline)
                .padding()

            FileChooserView(onSelect: { path in
                onSelect(path)
                dismiss()
            })
        }
        .frame(width: 600, height: 400)
    }
}
