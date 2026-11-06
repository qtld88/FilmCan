import SwiftUI

/// Rename and copy-mode hooks. Quick Copy passes them; the main window shows the tree read-only.
struct FolderTreeEditing {
    var autoEdit = true
    var copyContents = false
    var copyModeEdited = false
    var isEdited: (FolderTreeLine) -> Bool = { _ in false }
    var onSetCopyContents: (Bool) -> Void = { _ in }
    var onResetCopyMode: () -> Void = {}
    var onRename: (FolderTreeLine, String) -> Void = { _, _ in }
    var onReset: (FolderTreeLine) -> Void = { _ in }
}

/// Every folder a copy creates under a destination, fully expanded.
struct FolderTreePreview: View {
    let lines: [FolderTreeLine]
    var editing: FolderTreeEditing? = nil

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    FolderTreeRow(line: line, editing: editing)
                        .padding(.leading, CGFloat(line.depth) * 16)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(FilmCanTheme.background.opacity(0.6)))
        }
    }
}

/// One folder of the preview. Editable folders (top folder, Camera/Sound folder)
/// are renamed in place; the text lives in local state so a focused field never
/// writes back a stale suggestion.
private struct FolderTreeRow: View {
    let line: FolderTreeLine
    let editing: FolderTreeEditing?

    @State private var isEditing = false
    @State private var text = ""
    @State private var original = ""
    @FocusState private var focused: Bool

    private var canEdit: Bool { editing != nil }
    private var needsName: Bool { canEdit && line.isEditable && line.name.isEmpty }

    private var icon: String {
        switch line.role {
        case .folder: return "folder"
        case .copiedFolder: return "folder.fill"
        case .copiedFile: return "doc"
        case .contents: return "doc.on.doc"
        }
    }
    private var mono: Font { .system(size: 11, design: .monospaced) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).frame(width: 14)
            if isEditing, let editing {
                TextField(line.mediaKind.map { "\($0.displayName) folder name" } ?? "Folder name", text: $text)
                    .font(mono)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .frame(maxWidth: 260)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(text.isEmpty ? FilmCanTheme.brandRed : FilmCanTheme.brandYellow, lineWidth: 1))
                    .onChange(of: text) { editing.onRename(line, $0) }
                    .onSubmit { if !text.isEmpty { isEditing = false } }
                    .onExitCommand { text = original; isEditing = needsName }
                    .onChange(of: focused) { if !$0, !text.isEmpty { isEditing = false } }
            } else if let editing, line.togglesCopyMode {
                Text(line.name).font(mono)
                Button { editing.onSetCopyContents(!editing.copyContents) } label: {
                    Image(systemName: "pencil").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                .help(editing.copyContents ? "Copy the whole folder instead" : "Copy only its contents instead")
                if editing.copyModeEdited {
                    Button(action: editing.onResetCopyMode) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                    .help("Back to the preset's choice")
                }
            } else {
                Text(line.name).font(mono)
                if let editing, line.isEditable {
                    Button(action: startEditing) {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                    .help("Rename this folder")
                    if editing.isEdited(line) {
                        Button { editing.onReset(line) } label: {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                        }
                        .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                        .help("Back to the preset's name")
                    }
                }
            }
        }
        .foregroundColor(line.isNew ? FilmCanTheme.brandYellow : FilmCanTheme.textSecondary)
        .onAppear { if needsName && (editing?.autoEdit ?? false) { startEditing() } }
    }

    private func startEditing() {
        original = line.name
        text = line.name
        isEditing = true
        DispatchQueue.main.async { focused = true }
    }
}
